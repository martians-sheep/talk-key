import Foundation

final class LocalFormatter: FormatterProtocol {

    private static let fillerPatterns: [String] = [
        "えーと",
        "えーっと",
        "あのー",
        "まあ",
        "そのー",
        "なんか",
        "ええと",
        "うーん",
        "うーんと",
    ]

    // フィラー除去用の正規表現パターン
    // 「あの」は単独で使われる場合のみ除去（「あのね」「あのさ」等は残す）
    private static let fillerRegexPattern: String = {
        let escaped = fillerPatterns.map { NSRegularExpression.escapedPattern(for: $0) }
        let anoPattern = "あの(?![ねさ人方子日時頃])"
        return "(\(escaped.joined(separator: "|"))|\(anoPattern))"
    }()

    func format(text: String, mode: FormattingMode) async throws -> String {
        guard !text.isEmpty else { return "" }

        var result = text

        // 1. フィラー除去
        result = removeFillers(result)

        // 2. 連続空白の正規化
        result = normalizeWhitespace(result)

        // 3. 句読点の正規化
        result = normalizePunctuation(result)

        // 4. 改行の正規化
        result = normalizeNewlines(result)

        // 5. 文頭・文末のトリム
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    private func removeFillers(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: Self.fillerRegexPattern,
            options: []
        ) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private func normalizeWhitespace(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "[ \t]{2,}", options: []) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
    }

    private func normalizePunctuation(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "([。、？！!?．，]){2,}", options: []) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
    }

    private func normalizeNewlines(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\n{2,}", options: []) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "\n")
    }
}
