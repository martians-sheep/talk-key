import XCTest
import AVFoundation
@testable import TalkKey

final class FallbackTranscriberTests: XCTestCase {
    private var primary: MockTranscriber!
    private var fallback: MockTranscriber!
    private var transcriber: FallbackTranscriber!

    override func setUp() {
        super.setUp()
        primary = MockTranscriber()
        fallback = MockTranscriber()
        primary.transcriptionResult = Self.result("whisper の結果", .whisper)
        fallback.transcriptionResult = Self.result("apple の結果", .apple)
        transcriber = FallbackTranscriber(primary: primary, fallback: fallback, logger: MockLogger())
    }

    private static func result(_ text: String, _ engine: RecognitionSource) -> TranscriptionResult {
        TranscriptionResult(rawText: text, formattedText: nil, timestamp: Date(), duration: 1, engine: engine)
    }

    func test_start_startsBoth() throws {
        try transcriber.startTranscription()

        XCTAssertTrue(primary.startTranscriptionCalled)
        XCTAssertTrue(fallback.startTranscriptionCalled)
    }

    func test_feed_forwardsBufferToBoth() throws {
        try transcriber.startTranscription()

        transcriber.feedAudioBuffer(TestAudioBuffers.sine(duration: 0.1))

        XCTAssertEqual(primary.fedBuffers.count, 1)
        XCTAssertEqual(fallback.fedBuffers.count, 1)
    }

    func test_stop_whenPrimarySucceeds_returnsPrimaryResult() async throws {
        try transcriber.startTranscription()

        let result = try await transcriber.stopTranscription()

        XCTAssertEqual(result.rawText, "whisper の結果")
        XCTAssertEqual(result.engine, .whisper)
    }

    func test_stop_whenPrimarySucceeds_stillStopsFallback() async throws {
        try transcriber.startTranscription()

        _ = try await transcriber.stopTranscription()
        await transcriber.waitForPendingFallbackStopForTesting()

        XCTAssertTrue(fallback.stopTranscriptionCalled)
    }

    func test_stop_whenPrimaryFails_returnsFallbackResult() async throws {
        primary.stopTranscriptionError = TalkKeyError.transcriptionFailed("whisper-server is not available")
        try transcriber.startTranscription()

        let result = try await transcriber.stopTranscription()

        XCTAssertEqual(result.rawText, "apple の結果")
        XCTAssertEqual(result.engine, .apple)
    }

    func test_stop_whenPrimaryReturnsEmpty_usesNonEmptyFallback() async throws {
        primary.transcriptionResult = Self.result("", .whisper)
        try transcriber.startTranscription()

        let result = try await transcriber.stopTranscription()

        XCTAssertEqual(result.rawText, "apple の結果")
    }

    func test_stop_whenBothEmpty_returnsPrimaryEmpty() async throws {
        primary.transcriptionResult = Self.result("", .whisper)
        fallback.transcriptionResult = Self.result("", .apple)
        try transcriber.startTranscription()

        let result = try await transcriber.stopTranscription()

        XCTAssertEqual(result.rawText, "")
        XCTAssertEqual(result.engine, .whisper)
    }

    func test_stop_whenPrimaryReturnsEmptyAndFallbackFails_returnsPrimaryEmpty() async throws {
        primary.transcriptionResult = Self.result("", .whisper)
        fallback.stopTranscriptionError = TalkKeyError.transcriptionFailed("apple failed")
        try transcriber.startTranscription()

        let result = try await transcriber.stopTranscription()

        XCTAssertEqual(result.rawText, "")
    }

    func test_stop_whenBothFail_throws() async throws {
        primary.stopTranscriptionError = TalkKeyError.transcriptionFailed("whisper failed")
        fallback.stopTranscriptionError = TalkKeyError.transcriptionFailed("apple failed")
        try transcriber.startTranscription()

        do {
            _ = try await transcriber.stopTranscription()
            XCTFail("Expected error")
        } catch {}
    }

    func test_start_whenFallbackFailsToStart_continuesWithPrimaryOnly() async throws {
        fallback.startTranscriptionError = TalkKeyError.transcriptionFailed("Speech recognizer is not available")

        try transcriber.startTranscription()
        let result = try await transcriber.stopTranscription()

        XCTAssertEqual(result.rawText, "whisper の結果")
        XCTAssertFalse(fallback.stopTranscriptionCalled)
    }

    func test_start_whenPrimaryFailsToStart_usesFallbackOnly() async throws {
        primary.startTranscriptionError = TalkKeyError.transcriptionFailed("x")

        try transcriber.startTranscription()
        let result = try await transcriber.stopTranscription()

        XCTAssertEqual(result.rawText, "apple の結果")
        XCTAssertFalse(primary.stopTranscriptionCalled)
    }

    func test_start_whenBothFailToStart_throws() {
        primary.startTranscriptionError = TalkKeyError.transcriptionFailed("x")
        fallback.startTranscriptionError = TalkKeyError.transcriptionFailed("y")

        XCTAssertThrowsError(try transcriber.startTranscription())
    }
}
