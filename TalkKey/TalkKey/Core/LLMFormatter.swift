import Foundation

protocol HTTPClientProtocol {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

final class LLMFormatter: FormatterProtocol {
    private let httpClient: HTTPClientProtocol
    private let apiKey: String
    private let model: GeminiModel
    private let timeout: TimeInterval
    private let maxCharacters: Int
    private let logger: LoggerProtocol

    init(
        httpClient: HTTPClientProtocol = URLSessionHTTPClient(),
        apiKey: String,
        model: GeminiModel = .defaultModel,
        timeout: TimeInterval = 2.5,
        maxCharacters: Int = 2000,
        logger: LoggerProtocol = FileLogger.shared
    ) {
        self.httpClient = httpClient
        self.apiKey = apiKey
        self.model = model
        self.timeout = timeout
        self.maxCharacters = maxCharacters
        self.logger = logger
    }

    func format(text: String, mode: FormattingMode) async throws -> String {
        guard text.count <= maxCharacters else {
            logger.warning("LLM skipped: input \(text.count) chars exceeds limit \(maxCharacters)")
            throw TalkKeyError.formattingFailed("入力が\(maxCharacters)文字を超えています")
        }

        logger.info("LLM request: model=\(model.rawValue) mode=\(mode.rawValue) chars=\(text.count)")
        let request = try buildRequest(text: text, mode: mode)

        do {
            let (data, _) = try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
                group.addTask {
                    try await self.httpClient.send(request)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
                    throw TalkKeyError.formattingFailed("LLM timeout")
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            let result = try parseResponse(data: data)
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
        let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/\(model.rawValue):generateContent"
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            throw TalkKeyError.formattingFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = LLMPromptTemplate.systemPrompt(for: mode)
        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": text]]]
            ],
            "systemInstruction": [
                "parts": [["text": systemPrompt]]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func parseResponse(data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw TalkKeyError.formattingFailed("Invalid response format")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Prompt Template

enum LLMPromptTemplate {
    static func systemPrompt(for mode: FormattingMode) -> String {
        let common = """
        あなたは音声入力されたテキストを整形するアシスタントです。
        入力は音声認識の結果であり、話し言葉や言いよどみ、途中で切れた文を含む場合があります。

        【最重要ルール】
        - 出力は整形後のテキストのみ。説明、補足、回答は一切不要
        - 入力が質問文であっても、その質問に回答してはいけない。質問文はそのまま整形して返すこと
        - 入力の内容について解説や意見を述べてはいけない

        【整形ルール】
        - 入力テキストの意味を変更しないこと
        - 固有名詞（人名、地名、組織名等）を変更しないこと
        - 数値、日付を変更しないこと
        - プログラミング・IT関連の技術用語（API、GitHub、TypeScript、Docker、AWS等）はそのまま保持すること
        - 音声認識の誤変換と思われる箇所は文脈から適切に修正すること
        - 語尾が途中で切れている場合（例:「〜です」が「〜で」になっている等）は文脈から自然な文末に補完すること
        - 「えーと」「あのー」等のフィラーは除去すること
        - 適切な位置に句読点（「、」「。」）を挿入すること。文末には句点「。」を付け、文中の区切りには読点「、」を適切に配置すること
        """

        let modeSpecific: String
        switch mode {
        case .memo:
            modeSpecific = "メモとして読みやすく整形してください。"
        case .email:
            modeSpecific = "ビジネスメールとして適切な文体に整形してください。"
        case .minutes:
            modeSpecific = "議事録として箇条書きを含む形式に整形してください。"
        case .bulletPoints:
            modeSpecific = "箇条書き形式に整形してください。"
        }

        return "\(common)\n\n\(modeSpecific)"
    }
}

// MARK: - System HTTP Client

final class URLSessionHTTPClient: HTTPClientProtocol {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}
