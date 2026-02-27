import XCTest
@testable import TalkKey

final class FormattingPipelineTests: XCTestCase {

    private var localFormatter: MockLocalFormatter!
    private var llmFormatter: MockLLMFormatter!
    private var notificationSender: MockNotificationSender!

    override func setUp() {
        super.setUp()
        localFormatter = MockLocalFormatter()
        llmFormatter = MockLLMFormatter()
        notificationSender = MockNotificationSender()
    }

    // MARK: - LLM timeout fallback

    func testLLMTimeoutFallsBackToLocalResult() async throws {
        localFormatter.result = "ローカル整形済み"
        llmFormatter.error = TalkKeyError.formattingFailed("LLM timeout")

        let pipeline = FormattingPipeline(
            localFormatter: localFormatter,
            llmFormatter: llmFormatter,
            llmEnabled: true,
            notificationSender: notificationSender
        )

        let result = try await pipeline.format(text: "入力テキスト", mode: .memo)

        XCTAssertEqual(result, "ローカル整形済み")
    }

    // MARK: - LLM API error fallback

    func testLLMAPIErrorFallsBackToLocalResult() async throws {
        localFormatter.result = "ローカル整形済み"
        llmFormatter.error = TalkKeyError.formattingFailed("API error")

        let pipeline = FormattingPipeline(
            localFormatter: localFormatter,
            llmFormatter: llmFormatter,
            llmEnabled: true,
            notificationSender: notificationSender
        )

        let result = try await pipeline.format(text: "入力テキスト", mode: .memo)

        XCTAssertEqual(result, "ローカル整形済み")
    }

    // MARK: - LLM skip (over 2000 chars) fallback

    func testLLMSkipFallsBackToLocalResult() async throws {
        localFormatter.result = "ローカル整形済み（長文）"
        llmFormatter.error = TalkKeyError.formattingFailed("入力が2000文字を超えています")

        let pipeline = FormattingPipeline(
            localFormatter: localFormatter,
            llmFormatter: llmFormatter,
            llmEnabled: true,
            notificationSender: notificationSender
        )

        let result = try await pipeline.format(text: String(repeating: "あ", count: 2001), mode: .memo)

        XCTAssertEqual(result, "ローカル整形済み（長文）")
    }

    // MARK: - LLM disabled

    func testLLMDisabledUsesLocalOnly() async throws {
        localFormatter.result = "ローカルのみ"

        let pipeline = FormattingPipeline(
            localFormatter: localFormatter,
            llmFormatter: llmFormatter,
            llmEnabled: false,
            notificationSender: notificationSender
        )

        let result = try await pipeline.format(text: "入力", mode: .memo)

        XCTAssertEqual(result, "ローカルのみ")
        XCTAssertFalse(llmFormatter.formatCalled)
    }

    // MARK: - Fallback notification

    func testFallbackSendsNotification() async throws {
        localFormatter.result = "ローカル整形済み"
        llmFormatter.error = TalkKeyError.formattingFailed("LLM timeout")

        let pipeline = FormattingPipeline(
            localFormatter: localFormatter,
            llmFormatter: llmFormatter,
            llmEnabled: true,
            notificationSender: notificationSender
        )

        _ = try await pipeline.format(text: "入力テキスト", mode: .memo)

        XCTAssertTrue(notificationSender.sendCalled)
        XCTAssertTrue(notificationSender.lastMessage?.contains("整形スキップ") ?? false)
    }

    // MARK: - Successful LLM formatting

    func testSuccessfulLLMFormattingReturnsLLMResult() async throws {
        localFormatter.result = "ローカル整形済み"
        llmFormatter.result = "LLM整形済み"

        let pipeline = FormattingPipeline(
            localFormatter: localFormatter,
            llmFormatter: llmFormatter,
            llmEnabled: true,
            notificationSender: notificationSender
        )

        let result = try await pipeline.format(text: "入力", mode: .memo)

        XCTAssertEqual(result, "LLM整形済み")
        XCTAssertFalse(notificationSender.sendCalled)
    }
}

// MARK: - Mock formatters for pipeline tests

final class MockLocalFormatter: FormatterProtocol {
    var result: String?
    private(set) var formatCalled = false

    func format(text: String, mode: FormattingMode) async throws -> String {
        formatCalled = true
        return result ?? text
    }
}

final class MockLLMFormatter: FormatterProtocol {
    var result: String?
    var error: Error?
    private(set) var formatCalled = false

    func format(text: String, mode: FormattingMode) async throws -> String {
        formatCalled = true
        if let error = error { throw error }
        return result ?? text
    }
}
