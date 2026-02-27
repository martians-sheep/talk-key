import XCTest
import AVFoundation
@testable import TalkKey

final class TranscriberTests: XCTestCase {
    private var speechProvider: MockSpeechRecognizerProvider!
    private var transcriber: Transcriber!

    override func setUp() {
        super.setUp()
        speechProvider = MockSpeechRecognizerProvider()
        transcriber = Transcriber(speechProvider: speechProvider)
    }

    override func tearDown() {
        transcriber = nil
        speechProvider = nil
        super.tearDown()
    }

    // MARK: - Basic transcription

    func testTranscriptionReturnsTextResult() async throws {
        try transcriber.startTranscription()
        speechProvider.simulateResult(text: "こんにちは", isFinal: true)
        let result = try await transcriber.stopTranscription()
        XCTAssertEqual(result.rawText, "こんにちは")
    }

    func testIsFinalFlagUsesOnlyFinalResult() async throws {
        try transcriber.startTranscription()
        speechProvider.simulateResult(text: "こん", isFinal: false)
        speechProvider.simulateResult(text: "こんにちは世界", isFinal: true)
        let result = try await transcriber.stopTranscription()
        XCTAssertEqual(result.rawText, "こんにちは世界")
    }

    // MARK: - Locale

    func testRecognitionLocaleIsJapanese() throws {
        try transcriber.startTranscription()
        XCTAssertEqual(speechProvider.requestedLocale?.identifier, "ja-JP")
    }

    // MARK: - 50-second auto-stop

    func testAutoStopAfter50Seconds() async throws {
        try transcriber.startTranscription()
        speechProvider.simulateResult(text: "途中結果", isFinal: false)

        // Simulate timer fire
        transcriber.triggerAutoStopForTesting()

        let result = try await transcriber.stopTranscription()
        XCTAssertEqual(result.rawText, "途中結果")
        XCTAssertTrue(speechProvider.cancelCalled)
    }

    // MARK: - Error handling

    func testTranscriptionFailureReturnsError() async throws {
        speechProvider.shouldFailOnStart = true
        XCTAssertThrowsError(try transcriber.startTranscription()) { error in
            guard let tkError = error as? TalkKeyError else {
                XCTFail("Expected TalkKeyError")
                return
            }
            if case .transcriptionFailed = tkError {
                // expected
            } else {
                XCTFail("Expected transcriptionFailed")
            }
        }
    }

    func testRateLimitErrorHandling() async throws {
        try transcriber.startTranscription()
        speechProvider.simulateError(TalkKeyError.transcriptionFailed("Rate limit exceeded"))
        do {
            _ = try await transcriber.stopTranscription()
            XCTFail("Expected error")
        } catch {
            guard let tkError = error as? TalkKeyError else {
                XCTFail("Expected TalkKeyError")
                return
            }
            if case .transcriptionFailed = tkError {
                // expected
            } else {
                XCTFail("Expected transcriptionFailed")
            }
        }
    }

    // MARK: - No speech detected

    func testNoSpeechDetectedReturnsEmptyResult() async throws {
        try transcriber.startTranscription()
        let noSpeechError = NSError(domain: "kAFAssistantErrorDomain", code: 1101, userInfo: nil)
        speechProvider.simulateError(noSpeechError)
        let result = try await transcriber.stopTranscription()
        XCTAssertEqual(result.rawText, "")
    }

    // MARK: - Recognition cleanup on stop

    func testStopTranscriptionCancelsRecognition() async throws {
        try transcriber.startTranscription()
        speechProvider.simulateResult(text: "テスト", isFinal: false)
        _ = try await transcriber.stopTranscription()
        XCTAssertTrue(speechProvider.cancelCalled)
    }

    // MARK: - On-device recognition

    func testOnDeviceRecognitionAvailabilityCheck() {
        speechProvider.onDeviceAvailable = true
        XCTAssertTrue(transcriber.supportsOnDeviceRecognition)

        speechProvider.onDeviceAvailable = false
        XCTAssertFalse(transcriber.supportsOnDeviceRecognition)
    }

    // MARK: - Partial results

    func testPartialResultHandlerIsCalled() throws {
        var partialResults: [String] = []
        transcriber.partialResultHandler = { text in
            partialResults.append(text)
        }
        try transcriber.startTranscription()
        speechProvider.simulateResult(text: "こん", isFinal: false)
        speechProvider.simulateResult(text: "こんにちは", isFinal: false)
        XCTAssertEqual(partialResults, ["こん", "こんにちは"])
    }

    // MARK: - Consecutive sessions

    func testStaleErrorFromPreviousSessionIsIgnored() async throws {
        // First session: start and stop
        try transcriber.startTranscription()
        speechProvider.simulateResult(text: "最初", isFinal: true)
        _ = try await transcriber.stopTranscription()

        // Second session: start
        try transcriber.startTranscription()

        // Stale non-1101 error from first session fires (async cancel callback)
        speechProvider.simulateStaleError(
            NSError(domain: "kAFAssistantErrorDomain", code: 301, userInfo: [
                NSLocalizedDescriptionKey: "Connection failed"
            ])
        )

        // Second session produces valid result
        speechProvider.simulateResult(text: "二回目", isFinal: true)
        let result = try await transcriber.stopTranscription()

        // Should get second session's result, not throw due to stale error
        XCTAssertEqual(result.rawText, "二回目")
    }

    // MARK: - Feed audio buffer

    func testFeedAudioBufferForwardsToProvider() throws {
        try transcriber.startTranscription()
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        transcriber.feedAudioBuffer(buffer)
        XCTAssertEqual(speechProvider.fedBuffers.count, 1)
    }
}

// MARK: - Mock Speech Provider

final class MockSpeechRecognizerProvider: SpeechRecognizerProviderProtocol {
    var requestedLocale: Locale?
    var shouldFailOnStart = false
    var onDeviceAvailable = true
    private(set) var cancelCalled = false
    private(set) var fedBuffers: [AVAudioPCMBuffer] = []

    private var resultHandler: ((String, Bool) -> Void)?
    private var errorHandler: ((Error) -> Void)?
    private var previousErrorHandler: ((Error) -> Void)?

    var supportsOnDeviceRecognition: Bool { onDeviceAvailable }

    func startRecognition(
        locale: Locale,
        resultHandler: @escaping (String, Bool) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) throws {
        if shouldFailOnStart {
            throw TalkKeyError.transcriptionFailed("Speech recognition failed to start")
        }
        requestedLocale = locale
        self.resultHandler = resultHandler
        self.errorHandler = errorHandler
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        fedBuffers.append(buffer)
    }

    func cancelRecognition() {
        cancelCalled = true
        previousErrorHandler = errorHandler
        resultHandler = nil
        errorHandler = nil
    }

    func simulateResult(text: String, isFinal: Bool) {
        resultHandler?(text, isFinal)
    }

    func simulateError(_ error: Error) {
        errorHandler?(error)
    }

    func simulateStaleError(_ error: Error) {
        previousErrorHandler?(error)
    }
}
