import XCTest
@testable import TalkKey

final class LLMFormatterTests: XCTestCase {

    // MARK: - API request format

    func testSendsCorrectRequestFormat() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"整形されたテキスト"}]}}]}
        """
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key")

        _ = try await formatter.format(text: "テスト入力", mode: .memo)

        XCTAssertNotNil(client.lastRequest)
        let url = client.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("generativelanguage.googleapis.com"))
        XCTAssertTrue(url.contains("key=test-key"))
    }

    // MARK: - Response parsing

    func testExtractsFormattedTextFromResponse() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"きれいに整形されたテキスト"}]}}]}
        """
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key")

        let result = try await formatter.format(text: "入力テキスト", mode: .memo)

        XCTAssertEqual(result, "きれいに整形されたテキスト")
    }

    // MARK: - Timeout

    func testTimeoutReturnsError() async {
        let client = MockHTTPClient()
        client.delay = 5.0 // 5秒遅延（タイムアウト超過）
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", timeout: 0.1)

        do {
            _ = try await formatter.format(text: "テスト", mode: .memo)
            XCTFail("Expected timeout error")
        } catch {
            guard case TalkKeyError.formattingFailed(let message) = error else {
                XCTFail("Expected formattingFailed error, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("timeout") || message.contains("タイムアウト"))
        }
    }

    // MARK: - API error

    func testAPIErrorReturnsError() async {
        let client = MockHTTPClient()
        client.responseError = URLError(.badServerResponse)
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key")

        do {
            _ = try await formatter.format(text: "テスト", mode: .memo)
            XCTFail("Expected API error")
        } catch {
            guard case TalkKeyError.formattingFailed = error else {
                XCTFail("Expected formattingFailed error, got \(error)")
                return
            }
        }
    }

    // MARK: - Character limit

    func testSkipsWhenExceedingCharacterLimit() async {
        let client = MockHTTPClient()
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key")
        let longText = String(repeating: "あ", count: 2001)

        do {
            _ = try await formatter.format(text: longText, mode: .memo)
            XCTFail("Expected skip error")
        } catch {
            guard case TalkKeyError.formattingFailed(let message) = error else {
                XCTFail("Expected formattingFailed error, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("2000"))
        }
    }

    // MARK: - Prompt constraints

    func testPromptContainsConstraints() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"result"}]}}]}
        """
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key")

        _ = try await formatter.format(text: "テスト", mode: .memo)

        let body = client.lastRequestBody ?? ""
        XCTAssertTrue(body.contains("意味") || body.contains("変更"), "Prompt should contain meaning preservation constraint")
        XCTAssertTrue(body.contains("固有名詞") || body.contains("保持"), "Prompt should contain proper noun preservation")
    }

    // MARK: - Prompt design (2-3)

    func testDatePreservedInResponse() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"今日は2024年1月1日です。"}]}}]}
        """
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key")

        let result = try await formatter.format(text: "今日は2024年1月1日です", mode: .memo)

        XCTAssertTrue(result.contains("2024年1月1日"))
    }

    func testPersonNamePreservedInResponse() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"田中太郎さんに連絡してください。"}]}}]}
        """
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key")

        let result = try await formatter.format(text: "田中太郎さんに連絡してください", mode: .memo)

        XCTAssertTrue(result.contains("田中太郎"))
    }

    func testTechTermsPreservedInResponse() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"APIとGitHubとTypeScriptを使います。"}]}}]}
        """
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key")

        let result = try await formatter.format(text: "APIとGitHubとTypeScriptを使います", mode: .memo)

        XCTAssertTrue(result.contains("API"))
        XCTAssertTrue(result.contains("GitHub"))
        XCTAssertTrue(result.contains("TypeScript"))
    }

    func testModeSpecificPromptForEmail() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"result"}]}}]}
        """
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key")

        _ = try await formatter.format(text: "テスト", mode: .email)

        let body = client.lastRequestBody ?? ""
        XCTAssertTrue(body.contains("メール") || body.contains("email"), "Email mode prompt should mention email")
    }

    // MARK: - Prompt template unit tests

    func testPromptTemplateContainsCommonConstraints() {
        let prompt = LLMPromptTemplate.systemPrompt(for: .memo)
        XCTAssertTrue(prompt.contains("意味"))
        XCTAssertTrue(prompt.contains("固有名詞"))
        XCTAssertTrue(prompt.contains("数値"))
        XCTAssertTrue(prompt.contains("整形後のテキストのみ"))
    }

    func testPromptForbidsAnsweringQuestions() {
        let prompt = LLMPromptTemplate.systemPrompt(for: .memo)
        XCTAssertTrue(prompt.contains("回答") || prompt.contains("応答"), "Prompt should forbid answering questions")
        XCTAssertTrue(prompt.contains("質問"), "Prompt should mention questions")
    }

    func testPromptHandlesSpeechInputNoise() {
        let prompt = LLMPromptTemplate.systemPrompt(for: .memo)
        XCTAssertTrue(prompt.contains("音声") || prompt.contains("話し言葉"), "Prompt should mention speech input context")
    }

    func testPromptMentionsTechTerms() {
        let prompt = LLMPromptTemplate.systemPrompt(for: .memo)
        XCTAssertTrue(prompt.contains("技術用語") || prompt.contains("プログラミング"), "Prompt should mention tech terms preservation")
    }

    func testPromptHandlesTruncatedSentenceEndings() {
        let prompt = LLMPromptTemplate.systemPrompt(for: .memo)
        XCTAssertTrue(prompt.contains("語尾") || prompt.contains("文末"), "Prompt should mention truncated sentence ending completion")
    }

    func testPromptMentionsPunctuation() {
        let prompt = LLMPromptTemplate.systemPrompt(for: .memo)
        XCTAssertTrue(prompt.contains("句読点") || prompt.contains("句点") || prompt.contains("読点"), "Prompt should mention punctuation rules")
    }

    func testPromptTemplateVariesByMode() {
        let memo = LLMPromptTemplate.systemPrompt(for: .memo)
        let email = LLMPromptTemplate.systemPrompt(for: .email)
        let minutes = LLMPromptTemplate.systemPrompt(for: .minutes)
        let bullet = LLMPromptTemplate.systemPrompt(for: .bulletPoints)

        XCTAssertTrue(memo.contains("メモ"))
        XCTAssertTrue(email.contains("メール"))
        XCTAssertTrue(minutes.contains("議事録"))
        XCTAssertTrue(bullet.contains("箇条書き"))
    }

    // MARK: - Model selection

    func testDefaultModelIsGemini25Flash() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"result"}]}}]}
        """
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key")

        _ = try await formatter.format(text: "テスト", mode: .memo)

        let url = client.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("gemini-2.5-flash"), "Default model should be gemini-2.5-flash, got \(url)")
    }

    func testCustomModelInURL() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"result"}]}}]}
        """
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", model: .gemini25FlashLite)

        _ = try await formatter.format(text: "テスト", mode: .memo)

        let url = client.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("gemini-2.5-flash-lite"), "URL should contain gemini-2.5-flash-lite, got \(url)")
    }

    func testGemini25ProModelInURL() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"result"}]}}]}
        """
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", model: .gemini25Pro)

        _ = try await formatter.format(text: "テスト", mode: .memo)

        let url = client.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("gemini-2.5-pro"), "URL should contain gemini-2.5-pro, got \(url)")
    }

    // MARK: - Logging

    func testLogsRequestInfo() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"result"}]}}]}
        """
        let logger = MockLogger()
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", model: .gemini25Flash, logger: logger)

        _ = try await formatter.format(text: "テスト入力", mode: .email)

        let messages = logger.loggedMessages.map { $0.message }
        let requestLog = messages.first { $0.contains("gemini-2.5-flash") }
        XCTAssertNotNil(requestLog, "Should log model name")
        XCTAssertTrue(requestLog?.contains("email") ?? false, "Should log mode")
        XCTAssertTrue(requestLog?.contains("5") ?? false, "Should log input character count")
    }

    func testLogsResponseOnSuccess() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"整形されたテキスト"}]}}]}
        """
        let logger = MockLogger()
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", logger: logger)

        _ = try await formatter.format(text: "テスト", mode: .memo)

        let messages = logger.loggedMessages.map { $0.message }
        let responseLog = messages.first { $0.contains("response") || $0.contains("Response") }
        XCTAssertNotNil(responseLog, "Should log response info")
        XCTAssertTrue(responseLog?.contains("9") ?? false, "Should log output character count")
    }

    func testLogsErrorOnTimeout() async {
        let client = MockHTTPClient()
        client.delay = 5.0
        let logger = MockLogger()
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", timeout: 0.1, logger: logger)

        _ = try? await formatter.format(text: "テスト", mode: .memo)

        let errorMessages = logger.loggedMessages.filter { $0.level == .error }
        XCTAssertFalse(errorMessages.isEmpty, "Should log error on timeout")
        XCTAssertTrue(errorMessages.first?.message.contains("timeout") ?? false)
    }

    func testLogsErrorOnAPIError() async {
        let client = MockHTTPClient()
        client.responseError = URLError(.badServerResponse)
        let logger = MockLogger()
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", logger: logger)

        _ = try? await formatter.format(text: "テスト", mode: .memo)

        let errorMessages = logger.loggedMessages.filter { $0.level == .error }
        XCTAssertFalse(errorMessages.isEmpty, "Should log error on API error")
    }

    func testLogsWarningOnCharacterLimit() async {
        let client = MockHTTPClient()
        let logger = MockLogger()
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", logger: logger)
        let longText = String(repeating: "あ", count: 2001)

        _ = try? await formatter.format(text: longText, mode: .memo)

        let warnMessages = logger.loggedMessages.filter { $0.level == .warning }
        XCTAssertFalse(warnMessages.isEmpty, "Should log warning on character limit exceeded")
        XCTAssertTrue(warnMessages.first?.message.contains("2000") ?? false)
    }

    // MARK: - Response is formatted text only

    func testResponseTrimsExplanation() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"整形結果のみ"}]}}]}
        """
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key")

        let result = try await formatter.format(text: "テスト", mode: .memo)

        XCTAssertEqual(result, "整形結果のみ")
    }
}

// MARK: - Mock HTTP Client

final class MockHTTPClient: HTTPClientProtocol {
    var lastRequest: URLRequest?
    var lastRequestBody: String?
    var responseBody: String?
    var responseError: Error?
    var delay: TimeInterval = 0

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let body = request.httpBody {
            lastRequestBody = String(data: body, encoding: .utf8)
        }

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        if let error = responseError {
            throw error
        }

        let data = (responseBody ?? "").data(using: .utf8) ?? Data()
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
