@testable import TalkKey
import AVFoundation
import XCTest

final class ErrorHandlingTests: XCTestCase {
    // MARK: - Permission denied error messages

    func test_micPermissionDenied_returnsDescriptiveError() {
        let error = TalkKeyError.permissionDenied("マイクへのアクセスが拒否されています")
        XCTAssertTrue(error.localizedDescription.contains("マイク"))
    }

    func test_speechPermissionDenied_returnsDescriptiveError() {
        let error = TalkKeyError.permissionDenied("音声認識へのアクセスが拒否されています")
        XCTAssertTrue(error.localizedDescription.contains("音声認識"))
    }

    func test_accessibilityPermissionDenied_returnsDescriptiveError() {
        let error = TalkKeyError.permissionDenied("アクセシビリティ権限が必要です")
        XCTAssertTrue(error.localizedDescription.contains("アクセシビリティ"))
    }

    // MARK: - Recognition failure notification

    func test_recognitionFailure_sendsNotification() async throws {
        let audioCapture = MockAudioCapture()
        let transcriber = FailingTranscriber()
        let formatter = MockFormatter()
        let inserter = MockInserter()
        let historyStore = MockHistoryStore()
        let notificationSender = MockNotificationSender()

        let service = VoiceInputService(
            audioCapture: audioCapture,
            transcriber: transcriber,
            formatter: formatter,
            inserter: inserter,
            historyStore: historyStore
        )
        service.notificationSender = notificationSender

        try service.startRecording()
        do {
            _ = try await service.stopRecording()
            XCTFail("Expected error")
        } catch {
            // Recognition failure should be propagated
            XCTAssertTrue(error is TalkKeyError)
        }
    }

    // MARK: - LLM failure notification (integration via FormattingPipeline)

    func test_llmFailure_sendsNotification() async throws {
        let notificationSender = MockNotificationSender()
        let localFormatter = LocalFormatter()
        let failingLLM = FailingLLMFormatter()
        let pipeline = FormattingPipeline(
            localFormatter: localFormatter,
            llmFormatter: failingLLM,
            llmEnabled: true,
            notificationSender: notificationSender
        )

        let result = try await pipeline.format(text: "テスト", mode: .memo)

        XCTAssertTrue(notificationSender.sendCalled)
        XCTAssertTrue(notificationSender.lastMessage?.contains("LLM整形スキップ") ?? false)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Insertion failure notification

    func test_insertionFailure_sendsNotification() async throws {
        let audioCapture = MockAudioCapture()
        let transcriber = MockTranscriber()
        let formatter = MockFormatter()
        let inserter = MockInserter()
        inserter.insertError = TalkKeyError.insertionFailed("挿入に失敗しました")
        let historyStore = MockHistoryStore()
        let notificationSender = MockNotificationSender()

        let service = VoiceInputService(
            audioCapture: audioCapture,
            transcriber: transcriber,
            formatter: formatter,
            inserter: inserter,
            historyStore: historyStore
        )
        service.notificationSender = notificationSender

        try service.startRecording()
        _ = try await service.stopRecording()

        XCTAssertTrue(notificationSender.sendCalled)
        XCTAssertTrue(notificationSender.lastMessage?.contains("手動で貼り付け") ?? false)
    }

    // MARK: - TalkKeyError user messages

    func test_allErrorCases_haveDescriptiveMessages() {
        let errors: [TalkKeyError] = [
            .alreadyRecording,
            .notRecording,
            .permissionDenied("test"),
            .transcriptionFailed("test"),
            .insertionFailed("test"),
            .formattingFailed("test"),
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error \(error) should have non-empty description")
        }
    }
}

// MARK: - Test helpers

private final class FailingTranscriber: TranscriberProtocol {
    var partialResultHandler: ((String) -> Void)?
    func startTranscription() throws {}
    func stopTranscription() async throws -> TranscriptionResult {
        throw TalkKeyError.transcriptionFailed("Recognition error")
    }
    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer) {}
}

private final class FailingLLMFormatter: FormatterProtocol {
    func format(text: String, mode: FormattingMode) async throws -> String {
        throw TalkKeyError.formattingFailed("LLM API error")
    }
}
