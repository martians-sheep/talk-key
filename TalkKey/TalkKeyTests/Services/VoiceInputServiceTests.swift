import XCTest
import AVFoundation
@testable import TalkKey

final class VoiceInputServiceTests: XCTestCase {
    private var audioCapture: MockAudioCapture!
    private var transcriber: MockTranscriber!
    private var formatter: MockFormatter!
    private var inserter: MockInserter!
    private var historyStore: MockHistoryStore!
    private var service: VoiceInputService!

    override func setUp() {
        super.setUp()
        audioCapture = MockAudioCapture()
        transcriber = MockTranscriber()
        formatter = MockFormatter()
        inserter = MockInserter()
        historyStore = MockHistoryStore()
        service = VoiceInputService(
            audioCapture: audioCapture,
            transcriber: transcriber,
            formatter: formatter,
            inserter: inserter,
            historyStore: historyStore
        )
    }

    // MARK: - Basic state tests (from Phase 0)

    func testInitialStatusIsIdle() {
        XCTAssertEqual(service.status(), .idle)
    }

    func testStartRecordingChangesStatusToRecording() throws {
        try service.startRecording()
        XCTAssertEqual(service.status(), .recording)
        XCTAssertTrue(audioCapture.startCaptureCalled)
        XCTAssertTrue(transcriber.startTranscriptionCalled)
    }

    func testStopRecordingChangesStatusBackToIdle() async throws {
        try service.startRecording()
        let result = try await service.stopRecording()
        XCTAssertEqual(service.status(), .idle)
        XCTAssertTrue(audioCapture.stopCaptureCalled)
        XCTAssertTrue(transcriber.stopTranscriptionCalled)
        XCTAssertEqual(result.rawText, "mock transcription")
    }

    func testStartRecordingWhenAlreadyRecordingThrows() throws {
        try service.startRecording()
        XCTAssertThrowsError(try service.startRecording())
    }

    func testStopRecordingWhenNotRecordingThrows() async {
        do {
            _ = try await service.stopRecording()
            XCTFail("Expected error")
        } catch {
            // Expected
        }
    }

    // MARK: - Pipeline integration tests (Phase 1)

    func testStartRecordingConnectsAudioCaptureToTranscriber() throws {
        try service.startRecording()
        // audioBufferHandler should be set
        XCTAssertNotNil(audioCapture.audioBufferHandler)

        // Simulate a buffer arriving
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        audioCapture.audioBufferHandler?(buffer)

        XCTAssertEqual(transcriber.fedBuffers.count, 1)
    }

    func testStopRecordingReturnsTranscriptionResult() async throws {
        try service.startRecording()
        let result = try await service.stopRecording()
        XCTAssertFalse(result.rawText.isEmpty)
    }

    func testStateTransitionRecordingToProcessingToInsertingToIdle() async throws {
        var statusHistory: [ServiceStatus] = []
        service.onStatusChanged = { status in
            statusHistory.append(status)
        }

        try service.startRecording()
        _ = try await service.stopRecording()

        XCTAssertEqual(statusHistory, [.recording, .processing, .inserting, .idle])
    }

    func testTranscriptionFailureReturnsErrorStatus() async throws {
        transcriber.transcriptionResult = TranscriptionResult(
            rawText: "", formattedText: nil, timestamp: Date(), duration: 0
        )
        // Make stopTranscription throw
        let failingTranscriber = FailingMockTranscriber()
        let failService = VoiceInputService(
            audioCapture: audioCapture,
            transcriber: failingTranscriber,
            formatter: formatter,
            inserter: inserter,
            historyStore: historyStore
        )

        try failService.startRecording()
        do {
            _ = try await failService.stopRecording()
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(failService.status(), .error("Transcription failed: Recognition error"))
        }
    }
    // MARK: - Pipeline insertion tests (Phase 1.5)

    func testStopRecordingAutoInsertsResult() async throws {
        try service.startRecording()
        _ = try await service.stopRecording()
        XCTAssertTrue(inserter.insertCalled)
        XCTAssertEqual(inserter.insertedTexts.first, "mock transcription")
    }

    func testTranscriptionFailureSkipsInsertion() async throws {
        let failingTranscriber = FailingMockTranscriber()
        let failService = VoiceInputService(
            audioCapture: audioCapture,
            transcriber: failingTranscriber,
            formatter: formatter,
            inserter: inserter,
            historyStore: historyStore
        )

        try failService.startRecording()
        do {
            _ = try await failService.stopRecording()
            XCTFail("Expected error")
        } catch {
            XCTAssertFalse(inserter.insertCalled)
        }
    }

    func testEmptyTranscriptionSkipsInsertion() async throws {
        transcriber.transcriptionResult = TranscriptionResult(
            rawText: "", formattedText: nil, timestamp: Date(), duration: 0
        )
        try service.startRecording()
        _ = try await service.stopRecording()
        XCTAssertFalse(inserter.insertCalled)
    }

    // MARK: - Insertion failure recovery tests (Phase 1.5)

    func testInsertionFailureNotifiesUser() async throws {
        inserter.insertError = TalkKeyError.insertionFailed("Cmd+V failed")
        let notificationSender = MockNotificationSender()
        service.notificationSender = notificationSender

        try service.startRecording()
        _ = try await service.stopRecording()

        XCTAssertTrue(notificationSender.sendCalled)
        XCTAssertTrue(notificationSender.lastMessage?.contains("手動で貼り付け") ?? false)
    }

    func testInsertionFailureLeavesTextInClipboard() async throws {
        inserter.insertError = TalkKeyError.insertionFailed("Cmd+V failed")

        try service.startRecording()
        let result = try await service.stopRecording()

        // Even though insertion failed, result is still returned
        XCTAssertEqual(result.rawText, "mock transcription")
        // Service should return to idle (not error) since text is in clipboard
        XCTAssertEqual(service.status(), .idle)
    }
    // MARK: - History integration tests (Phase 3)

    func testSuccessfulRecognitionSavesToHistory() async throws {
        try service.startRecording()
        _ = try await service.stopRecording()

        XCTAssertEqual(historyStore.savedEntries.count, 1)
    }

    func testRecognitionFailureSavesFailureRecordToHistory() async throws {
        let failingTranscriber = FailingMockTranscriber()
        let failService = VoiceInputService(
            audioCapture: audioCapture,
            transcriber: failingTranscriber,
            formatter: formatter,
            inserter: inserter,
            historyStore: historyStore
        )

        try failService.startRecording()
        do {
            _ = try await failService.stopRecording()
            XCTFail("Expected error")
        } catch {
            // Failure record should still be saved
            XCTAssertEqual(historyStore.savedEntries.count, 1)
            XCTAssertTrue(historyStore.savedEntries.first?.result.rawText.isEmpty ?? true)
        }
    }

    func testHistoryEntryContainsAllRequiredFields() async throws {
        try service.startRecording()
        _ = try await service.stopRecording()

        let entry = historyStore.savedEntries.first
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.result.rawText, "mock transcription")
        XCTAssertNotNil(entry?.result.formattedText)
        XCTAssertEqual(entry?.mode, .memo)
        XCTAssertNotNil(entry?.createdAt)
    }
}

// MARK: - Failing mock for error test

final class MockNotificationSender: NotificationSenderProtocol {
    private(set) var sendCalled = false
    private(set) var lastTitle: String?
    private(set) var lastMessage: String?

    func send(title: String, message: String) {
        sendCalled = true
        lastTitle = title
        lastMessage = message
    }
}

private final class FailingMockTranscriber: TranscriberProtocol {
    var partialResultHandler: ((String) -> Void)?
    func startTranscription() throws {}
    func stopTranscription() async throws -> TranscriptionResult {
        throw TalkKeyError.transcriptionFailed("Recognition error")
    }
    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer) {}
}
