import XCTest
@testable import TalkKey

final class ClaudeFormatterTests: XCTestCase {
    private var client: MockHTTPClient!
    private var logger: MockLogger!

    override func setUp() {
        super.setUp()
        client = MockHTTPClient()
        logger = MockLogger()
    }

    private func makeFormatter(
        model: String = ClaudeFormatter.defaultModel,
        timeout: TimeInterval = ClaudeFormatter.defaultTimeout,
        vocabularyTerms: [String] = []
    ) -> ClaudeFormatter {
        ClaudeFormatter(
            httpClient: client,
            apiKey: "sk-test-secret",
            model: model,
            timeout: timeout,
            vocabularyTerms: vocabularyTerms,
            logger: logger
        )
    }

    private func requestJSON() throws -> [String: Any] {
        let data = try XCTUnwrap(client.lastRequest?.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func textResponse(_ text: String, stopReason: String = "end_turn") -> String {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"id":"msg_1","type":"message","role":"assistant","content":[{"type":"text","text":""# + escaped + #""}],"stop_reason":""# + stopReason + #""}"#
    }

    // MARK: - Request shape

    func test_format_postsToMessagesEndpointWithRequiredHeaders() async throws {
        client.responseBody = Self.textResponse("整形済み")

        _ = try await makeFormatter().format(text: "テスト", mode: .memo)

        let request = try XCTUnwrap(client.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-test-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(request.value(forHTTPHeaderField: "content-type"), "application/json")
    }

    func test_format_sendsModelMaxTokensThinkingDisabledAndLowEffort() async throws {
        client.responseBody = Self.textResponse("整形済み")

        _ = try await makeFormatter().format(text: "テスト", mode: .memo)

        let json = try requestJSON()
        XCTAssertEqual(json["model"] as? String, "claude-haiku-5-5")
        XCTAssertEqual(json["max_tokens"] as? Int, 1024)
        XCTAssertEqual((json["thinking"] as? [String: Any])?["type"] as? String, "disabled")
        XCTAssertEqual((json["output_config"] as? [String: Any])?["effort"] as? String, "low")
    }

    func test_format_withCustomModel_sendsThatModel() async throws {
        client.responseBody = Self.textResponse("整形済み")

        _ = try await makeFormatter(model: "claude-sonnet-5").format(text: "テスト", mode: .memo)

        XCTAssertEqual(try requestJSON()["model"] as? String, "claude-sonnet-5")
    }

    func test_format_sendsSharedSystemPromptWithVocabulary() async throws {
        client.responseBody = Self.textResponse("整形済み")

        _ = try await makeFormatter(vocabularyTerms: ["施行日"]).format(text: "テスト", mode: .memo)

        let system = try requestJSON()["system"] as? String
        XCTAssertEqual(system, LLMPromptTemplate.systemPrompt(for: .memo, vocabularyTerms: ["施行日"]))
    }

    func test_format_sendsSingleUserMessageWithWrappedTranscriptAndNoPrefill() async throws {
        client.responseBody = Self.textResponse("整形済み")

        _ = try await makeFormatter().format(text: "返信しておいて", mode: .memo)

        let messages = try XCTUnwrap(try requestJSON()["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "<transcript>\n返信しておいて\n</transcript>")
    }

    // MARK: - Response parsing

    func test_format_joinsTextBlocksAndIgnoresOtherBlocks() async throws {
        client.responseBody = #"{"content":[{"type":"thinking","thinking":"x"},{"type":"text","text":"前半、"},{"type":"text","text":"後半。\n"}],"stop_reason":"end_turn"}"#

        let result = try await makeFormatter().format(text: "テスト", mode: .memo)

        XCTAssertEqual(result, "前半、後半。")
    }

    func test_format_stripsEchoedTranscriptTags() async throws {
        client.responseBody = Self.textResponse("<transcript>\\n整形済み。\\n</transcript>")

        let result = try await makeFormatter().format(text: "テスト", mode: .memo)

        XCTAssertEqual(result, "整形済み。")
    }

    func test_format_withRefusal_throws() async {
        client.responseBody = Self.textResponse("", stopReason: "refusal")

        await assertFormattingFails()
    }

    func test_format_withMaxTokens_throws() async {
        client.responseBody = Self.textResponse("途中まで", stopReason: "max_tokens")

        await assertFormattingFails()
    }

    func test_format_withEmptyText_throws() async {
        client.responseBody = #"{"content":[],"stop_reason":"end_turn"}"#

        await assertFormattingFails()
    }

    // MARK: - Errors

    func test_format_withHTTPError_throwsAndLogsStatusAndBodyWithoutKey() async {
        client.responseStatusCode = 401
        client.responseBody = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key sk-test-secret"}}"#

        await assertFormattingFails()

        let logs = logger.loggedMessages.map(\.message).joined(separator: "\n")
        XCTAssertTrue(logs.contains("401"))
        XCTAssertTrue(logs.contains("authentication_error"))
        XCTAssertFalse(logs.contains("sk-test-secret"), "API key must never be logged")
    }

    func test_format_withTimeout_throws() async {
        client.delay = 5
        client.responseBody = Self.textResponse("整形済み")

        let formatter = makeFormatter(timeout: 0.1)
        do {
            _ = try await formatter.format(text: "テスト", mode: .memo)
            XCTFail("Expected timeout")
        } catch {
            guard case TalkKeyError.formattingFailed(let message) = error else {
                return XCTFail("Expected formattingFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("timeout"))
        }
    }

    func test_format_withTooLongInput_throwsWithoutRequest() async {
        let longText = String(repeating: "あ", count: 2001)

        _ = try? await makeFormatter().format(text: longText, mode: .memo)

        XCTAssertTrue(client.requests.isEmpty)
    }

    func test_defaults_matchSpec() {
        XCTAssertEqual(ClaudeFormatter.defaultModel, "claude-haiku-5-5")
        XCTAssertEqual(ClaudeFormatter.defaultTimeout, LLMFormatter.defaultTimeout)
    }

    private func assertFormattingFails(file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await makeFormatter().format(text: "テスト", mode: .memo)
            XCTFail("Expected formattingFailed", file: file, line: line)
        } catch {
            guard case TalkKeyError.formattingFailed = error else {
                return XCTFail("Expected formattingFailed, got \(error)", file: file, line: line)
            }
        }
    }
}
