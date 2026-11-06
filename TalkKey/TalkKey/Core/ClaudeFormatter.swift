import Foundation

final class ClaudeFormatter: FormatterProtocol {
    static let defaultModel = "claude-haiku-5-5"
    static let defaultTimeout: TimeInterval = LLMFormatter.defaultTimeout

    private enum Constants {
        static let endpoint = "https://api.anthropic.com/v1/messages"
        static let apiVersion = "2023-06-01"
        static let maxTokens = 1024
        static let errorBodyLogLimit = 300
        // 途中で切れた・拒否された応答は整形結果として使わず、ローカル整形に任せる
        static let failingStopReasons: Set<String> = ["refusal", "max_tokens"]
    }

    private let httpClient: HTTPClientProtocol
    private let apiKey: String
    private let model: String
    private let timeout: TimeInterval
    private let maxCharacters: Int
    private let vocabularyTerms: [String]
    private let logger: LoggerProtocol

    init(
        httpClient: HTTPClientProtocol = URLSessionHTTPClient(),
        apiKey: String,
        model: String = ClaudeFormatter.defaultModel,
        timeout: TimeInterval = ClaudeFormatter.defaultTimeout,
        maxCharacters: Int = 2000,
        vocabularyTerms: [String] = [],
        logger: LoggerProtocol = FileLogger.shared
    ) {
        self.httpClient = httpClient
        self.apiKey = apiKey
        self.model = model
        self.timeout = timeout
        self.maxCharacters = maxCharacters
        self.vocabularyTerms = vocabularyTerms
        self.logger = logger
    }

    func format(text: String, mode: FormattingMode) async throws -> String {
        guard text.count <= maxCharacters else {
            logger.warning("LLM skipped: input \(text.count) chars exceeds limit \(maxCharacters)")
            throw TalkKeyError.formattingFailed("入力が\(maxCharacters)文字を超えています")
        }

        logger.info("LLM request: model=\(model) mode=\(mode.rawValue) chars=\(text.count)")
        let request = try buildRequest(text: text, mode: mode)

        do {
            let (data, response) = try await withTimeout(timeout) {
                try await self.httpClient.send(request)
            }
            let result = try handle(data: data, response: response)
            logger.info("LLM response: chars=\(result.count)")
            return result
        } catch let error as TalkKeyError {
            logger.error("LLM error: \(error.localizedDescription)")
            throw error
        } catch {
            logger.error("LLM error: \(error.localizedDescription)")
            throw TalkKeyError.formattingFailed("API error: \(error.localizedDescription)")
        }
    }

    private func buildRequest(text: String, mode: FormattingMode) throws -> URLRequest {
        guard let url = URL(string: Constants.endpoint) else {
            throw TalkKeyError.formattingFailed("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Constants.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        // 思考を有効にすると数秒遅くなり、出力に考えごとが混ざるため無効にする
        let body: [String: Any] = [
            "model": model,
            "max_tokens": Constants.maxTokens,
            "system": LLMPromptTemplate.systemPrompt(for: mode, vocabularyTerms: vocabularyTerms),
            "messages": [
                ["role": "user", "content": LLMPromptTemplate.wrapTranscript(text)]
            ],
            "thinking": ["type": "disabled"],
            "output_config": ["effort": "low"],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func handle(data: Data, response: URLResponse) throws -> String {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = HTTPErrorBody.prefix(of: data, limit: Constants.errorBodyLogLimit, redacting: apiKey)
            logger.error("LLM HTTP \(status): \(body)")
            throw TalkKeyError.formattingFailed("HTTP \(status)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw TalkKeyError.formattingFailed("Invalid response format")
        }
        if let stopReason = json["stop_reason"] as? String, Constants.failingStopReasons.contains(stopReason) {
            throw TalkKeyError.formattingFailed("stop_reason=\(stopReason)")
        }

        let text = content
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        let cleaned = LLMPromptTemplate.stripTranscriptTags(text)
        guard !cleaned.isEmpty else {
            throw TalkKeyError.formattingFailed("Empty response")
        }
        return cleaned
    }
}
