import Foundation

final class FormattingPipeline: FormatterProtocol {
    private let localFormatter: FormatterProtocol
    private let llmFormatter: FormatterProtocol?
    private let llmEnabled: Bool
    private let notificationSender: NotificationSenderProtocol?
    private let logger: LoggerProtocol

    init(
        localFormatter: FormatterProtocol,
        llmFormatter: FormatterProtocol? = nil,
        llmEnabled: Bool = false,
        notificationSender: NotificationSenderProtocol? = nil,
        logger: LoggerProtocol = FileLogger.shared
    ) {
        self.localFormatter = localFormatter
        self.llmFormatter = llmFormatter
        self.llmEnabled = llmEnabled
        self.notificationSender = notificationSender
        self.logger = logger
    }

    func format(text: String, mode: FormattingMode) async throws -> String {
        let localResult = try await localFormatter.format(text: text, mode: mode)

        guard llmEnabled, let llmFormatter = llmFormatter else {
            logger.debug("LLM formatting disabled, using local result")
            return localResult
        }

        do {
            let result = try await llmFormatter.format(text: localResult, mode: mode)
            logger.debug("LLM formatting completed")
            return result
        } catch {
            logger.warning("LLM formatting failed, falling back to local: \(error.localizedDescription)")
            notificationSender?.send(
                title: "TalkKey",
                message: "LLM整形スキップ：ローカル整形結果を使用します。"
            )
            return localResult
        }
    }
}
