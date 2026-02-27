import Foundation

struct LogEntry {
    let timestamp: String
    let level: LogLevel
    let message: String
    let rawLine: String

    init?(rawLine: String) {
        guard !rawLine.isEmpty else { return nil }

        let pattern = #"^(\S+)\s+\[(\w+)\]\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: rawLine,
                range: NSRange(rawLine.startIndex..., in: rawLine)
              ),
              match.numberOfRanges == 4,
              let tsRange = Range(match.range(at: 1), in: rawLine),
              let levelRange = Range(match.range(at: 2), in: rawLine),
              let msgRange = Range(match.range(at: 3), in: rawLine),
              let level = LogLevel(rawValue: String(rawLine[levelRange])) else {
            return nil
        }

        self.timestamp = String(rawLine[tsRange])
        self.level = level
        self.message = String(rawLine[msgRange])
        self.rawLine = rawLine
    }
}
