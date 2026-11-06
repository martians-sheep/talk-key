import Foundation

final class LLMFormatter: FormatterProtocol {
    static let defaultTimeout: TimeInterval = 4.0

    private enum Constants {
        static let endpointBase = "https://generativelanguage.googleapis.com/v1beta/models/"
        static let errorBodyLogLimit = 300
        static let badRequestStatus = 400
    }

    private let httpClient: HTTPClientProtocol
    private let apiKey: String
    private let model: GeminiModel
    private let timeout: TimeInterval
    private let maxCharacters: Int
    private let vocabularyTerms: [String]
    private let logger: LoggerProtocol

    // thinkingConfig は未検証の設定のため、400 が返ったら以後は付けずに送る
    private let thinkingLock = NSLock()
    private var sendsThinkingConfig = true

    init(
        httpClient: HTTPClientProtocol = URLSessionHTTPClient(),
        apiKey: String,
        model: GeminiModel = .defaultModel,
        timeout: TimeInterval = LLMFormatter.defaultTimeout,
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

        logger.info("LLM request: model=\(model.rawValue) mode=\(mode.rawValue) chars=\(text.count)")

        do {
            let result = try await withTimeout(timeout) {
                try await self.sendWithThinkingFallback(text: text, mode: mode)
            }
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

    private func sendWithThinkingFallback(text: String, mode: FormattingMode) async throws -> String {
        let useThinking = thinkingLock.withLock { sendsThinkingConfig }
        let (data, status) = try await send(text: text, mode: mode, includeThinkingConfig: useThinking)

        if status == Constants.badRequestStatus && useThinking {
            logger.warning("LLM 400 with thinkingConfig; retrying once without it")
            thinkingLock.withLock { sendsThinkingConfig = false }
            let (retryData, retryStatus) = try await send(text: text, mode: mode, includeThinkingConfig: false)
            return try handle(data: retryData, status: retryStatus)
        }
        return try handle(data: data, status: status)
    }

    private func send(text: String, mode: FormattingMode, includeThinkingConfig: Bool) async throws -> (Data, Int) {
        let request = try buildRequest(text: text, mode: mode, includeThinkingConfig: includeThinkingConfig)
        let (data, response) = try await httpClient.send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }

    private func handle(data: Data, status: Int) throws -> String {
        guard (200..<300).contains(status) else {
            let body = HTTPErrorBody.prefix(of: data, limit: Constants.errorBodyLogLimit, redacting: apiKey)
            logger.error("LLM HTTP \(status): \(body)")
            throw TalkKeyError.formattingFailed("HTTP \(status)")
        }
        return try parseResponse(data: data)
    }

    private func buildRequest(text: String, mode: FormattingMode, includeThinkingConfig: Bool) throws -> URLRequest {
        guard let url = URL(string: "\(Constants.endpointBase)\(model.rawValue):generateContent") else {
            throw TalkKeyError.formattingFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let systemPrompt = LLMPromptTemplate.systemPrompt(for: mode, vocabularyTerms: vocabularyTerms)
        var body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": LLMPromptTemplate.wrapTranscript(text)]]]
            ],
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ]
        ]
        if includeThinkingConfig {
            // 整形に推論は不要なため、思考を最小にして応答を速くする
            body["generationConfig"] = ["thinkingConfig": ["thinkingLevel": "minimal"]]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseResponse(data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw TalkKeyError.formattingFailed("Invalid response format")
        }
        let text = parts.compactMap { $0["text"] as? String }.joined()
        guard !text.isEmpty else {
            throw TalkKeyError.formattingFailed("Invalid response format")
        }
        return LLMPromptTemplate.stripTranscriptTags(text)
    }
}
