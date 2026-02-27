import Foundation

enum LogFilter {
    case all
    case llmOnly
    case errorsOnly
}

final class LogFileReader {
    private let logFileURL: URL

    init(logFileURL: URL? = nil) {
        self.logFileURL = logFileURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/TalkKey/talkkey.log")
    }

    func readAll() -> [LogEntry] {
        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return []
        }
        return content
            .components(separatedBy: "\n")
            .compactMap { LogEntry(rawLine: $0) }
    }

    func readFiltered(filter: LogFilter) -> [LogEntry] {
        let all = readAll()
        switch filter {
        case .all:
            return all
        case .llmOnly:
            return all.filter { $0.message.contains("LLM ") }
        case .errorsOnly:
            return all.filter { $0.level >= .warning }
        }
    }
}
