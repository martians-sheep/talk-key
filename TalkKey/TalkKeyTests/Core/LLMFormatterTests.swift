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
        XCTAssertFalse(url.contains("key="), "API key must not be sent in the URL query")
        XCTAssertEqual(client.lastRequest?.value(forHTTPHeaderField: "x-goog-api-key"), "test-key")
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

    func test_format_withDefaultModel_usesGemini38Flash() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"result"}]}}]}
        """
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key")

        _ = try await formatter.format(text: "テスト", mode: .memo)

        let url = client.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("models/gemini-3.8-flash:"), "Default model should be gemini-3.8-flash, got \(url)")
    }

    func testCustomModelInURL() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"result"}]}}]}
        """
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", model: .gemini35FlashLite)

        _ = try await formatter.format(text: "テスト", mode: .memo)

        let url = client.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("gemini-3.5-flash-lite"), "URL should contain gemini-3.5-flash-lite, got \(url)")
    }

    func test_format_withFlashLatestAlias_usesAliasInURL() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"result"}]}}]}
        """
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", model: .geminiFlashLatest)

        _ = try await formatter.format(text: "テスト", mode: .memo)

        let url = client.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("gemini-flash-latest"), "URL should contain gemini-flash-latest, got \(url)")
    }

    // MARK: - Logging

    func testLogsRequestInfo() async throws {
        let client = MockHTTPClient()
        client.responseBody = """
        {"candidates":[{"content":{"parts":[{"text":"result"}]}}]}
        """
        let logger = MockLogger()
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", model: .gemini38Flash, logger: logger)

        _ = try await formatter.format(text: "テスト入力", mode: .email)

        let messages = logger.loggedMessages.map { $0.message }
        let requestLog = messages.first { $0.contains("gemini-3.8-flash") }
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

    // MARK: - HTTP status handling

    func test_format_withHTTPErrorStatus_throwsAndLogsStatusAndBodyWithoutKey() async {
        let client = MockHTTPClient()
        client.responseStatusCode = 402
        client.responseBody = #"{"error":{"code":402,"message":"Payment required for key test-key"}}"#
        let logger = MockLogger()
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", logger: logger)

        do {
            _ = try await formatter.format(text: "テスト", mode: .memo)
            XCTFail("Expected error")
        } catch {
            guard case TalkKeyError.formattingFailed(let message) = error else {
                XCTFail("Expected formattingFailed, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("402"))
        }

        let allLogs = logger.loggedMessages.map(\.message).joined(separator: "\n")
        XCTAssertTrue(allLogs.contains("402"))
        XCTAssertTrue(allLogs.contains("Payment required"))
        XCTAssertFalse(allLogs.contains("test-key"), "API key must never be logged")
    }

    func test_format_withServerError_throws() async {
        let client = MockHTTPClient()
        client.responseStatusCode = 503
        client.responseBody = "unavailable"
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", logger: MockLogger())

        do {
            _ = try await formatter.format(text: "テスト", mode: .memo)
            XCTFail("Expected error")
        } catch {
            guard case TalkKeyError.formattingFailed = error else {
                XCTFail("Expected formattingFailed, got \(error)")
                return
            }
        }
    }

    // MARK: - Thinking config

    func test_format_sendsMinimalThinkingConfig() async throws {
        let client = MockHTTPClient()
        client.responseBody = Self.okBody
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", logger: MockLogger())

        _ = try await formatter.format(text: "テスト", mode: .memo)

        let body = client.lastRequestBody ?? ""
        XCTAssertTrue(body.contains("thinkingConfig"))
        XCTAssertTrue(body.contains("minimal"))
    }

    func test_format_when400WithThinkingConfig_retriesOnceWithoutItAndKeepsItOff() async throws {
        let client = MockHTTPClient()
        client.stubbedResponses = [
            .init(statusCode: 400, body: #"{"error":{"message":"Unknown name thinkingLevel"}}"#),
            .init(statusCode: 200, body: Self.okBody),
            .init(statusCode: 200, body: Self.okBody),
        ]
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", logger: MockLogger())

        let first = try await formatter.format(text: "テスト", mode: .memo)
        _ = try await formatter.format(text: "テスト2", mode: .memo)

        XCTAssertEqual(first, "result")
        XCTAssertEqual(client.requests.count, 3)
        let bodies = client.requests.map { String(data: $0.httpBody ?? Data(), encoding: .utf8) ?? "" }
        XCTAssertTrue(bodies[0].contains("thinkingConfig"))
        XCTAssertFalse(bodies[1].contains("thinkingConfig"))
        XCTAssertFalse(bodies[2].contains("thinkingConfig"))
    }

    func test_format_when400Repeats_doesNotRetryMoreThanOnce() async {
        let client = MockHTTPClient()
        client.responseStatusCode = 400
        client.responseBody = "bad request"
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", logger: MockLogger())

        _ = try? await formatter.format(text: "テスト", mode: .memo)

        XCTAssertEqual(client.requests.count, 2)
    }

    func test_defaultTimeout_isAboutFourSeconds() {
        XCTAssertEqual(LLMFormatter.defaultTimeout, 4.0)
    }

    // MARK: - Vocabulary hints

    func test_format_withVocabularyTerms_includesThemInSystemPrompt() async throws {
        let client = MockHTTPClient()
        client.responseBody = Self.okBody
        let formatter = LLMFormatter(
            httpClient: client,
            apiKey: "test-key",
            vocabularyTerms: ["TalkKey", "whisper.cpp"],
            logger: MockLogger()
        )

        _ = try await formatter.format(text: "テスト", mode: .memo)

        let body = client.lastRequestBody ?? ""
        XCTAssertTrue(body.contains("TalkKey"))
        XCTAssertTrue(body.contains("whisper.cpp"))
    }

    // MARK: - Prompt: fillers and restatements

    func test_systemPrompt_mentionsFillersToRemove() {
        let prompt = LLMPromptTemplate.systemPrompt(for: .memo)
        for filler in ["えーと", "あのー", "まあ", "なんか", "うーん"] {
            XCTAssertTrue(prompt.contains(filler), "Prompt should list filler \(filler)")
        }
    }

    func test_systemPrompt_explainsRestatementsKeepLastPhrase() {
        let prompt = LLMPromptTemplate.systemPrompt(for: .memo)
        XCTAssertTrue(prompt.contains("言い直し"))
        XCTAssertTrue(prompt.contains("じゃなくて"))
        XCTAssertTrue(prompt.contains("いや"))
    }

    func test_systemPrompt_mentionsRepeatedWords() {
        let prompt = LLMPromptTemplate.systemPrompt(for: .memo)
        XCTAssertTrue(prompt.contains("繰り返し") || prompt.contains("重複"))
    }

    func test_systemPrompt_forbidsAddingExplanations() {
        let prompt = LLMPromptTemplate.systemPrompt(for: .memo)
        XCTAssertTrue(prompt.contains("説明"))
    }

    func test_systemPrompt_withVocabulary_listsTermsAndUsesThemForCorrection() {
        let prompt = LLMPromptTemplate.systemPrompt(for: .memo, vocabularyTerms: ["TalkKey", "Agent Board"])
        XCTAssertTrue(prompt.contains("用語のヒント"))
        XCTAssertTrue(prompt.contains("TalkKey"))
        XCTAssertTrue(prompt.contains("Agent Board"))
    }

    func test_systemPrompt_withoutVocabulary_omitsVocabularySection() {
        let prompt = LLMPromptTemplate.systemPrompt(for: .memo, vocabularyTerms: [])
        XCTAssertFalse(prompt.contains("【用語のヒント】"))
    }

    private static let okBody = #"{"candidates":[{"content":{"parts":[{"text":"result"}]}}]}"#

    // MARK: - Transcript wrapping (prevents executing the dictated request)

    func test_wrapTranscript_wrapsInTranscriptTags() {
        XCTAssertEqual(
            LLMPromptTemplate.wrapTranscript("送っておいて"),
            "<transcript>\n送っておいて\n</transcript>"
        )
    }

    func test_format_sendsTranscriptWrappedInTags() async throws {
        let client = MockHTTPClient()
        client.responseBody = Self.okBody
        let formatter = LLMFormatter(httpClient: client, apiKey: "test-key", logger: MockLogger())

        _ = try await formatter.format(text: "返信して", mode: .memo)

        let json = try JSONSerialization.jsonObject(with: client.lastRequest?.httpBody ?? Data()) as? [String: Any]
        let contents = json?["contents"] as? [[String: Any]]
        let parts = contents?.first?["parts"] as? [[String: Any]]
        XCTAssertEqual(parts?.first?["text"] as? String, "<transcript>\n返信して\n</transcript>")
    }

    func test_systemPrompt_explainsTranscriptIsNotAddressedToModel() {
        let prompt = LLMPromptTemplate.systemPrompt(for: .memo)
        XCTAssertTrue(prompt.contains("<transcript>"))
        XCTAssertTrue(prompt.contains("あなた宛てではない"))
        XCTAssertTrue(prompt.contains("実行"))
        XCTAssertTrue(prompt.contains("って送っておいて"))
    }

    func test_systemPrompt_keepsSpeakerTone() {
        let prompt = LLMPromptTemplate.systemPrompt(for: .memo)
        XCTAssertTrue(prompt.contains("口調"))
    }

    func test_systemPrompt_correctsMisrecognitionsCloseToVocabulary() {
        let prompt = LLMPromptTemplate.systemPrompt(for: .memo, vocabularyTerms: ["施行日"])
        XCTAssertTrue(prompt.contains("音が近い"))
        XCTAssertTrue(prompt.contains("試行日→施行日"))
    }
}
