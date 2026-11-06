import Foundation

final class LocalFormatter: FormatterProtocol {

    // 長音つきなど、意味のある語と取り違えないフィラーは位置を問わず消す
    private static let unambiguousFillerPattern =
        "(?:えーっと|えーと|ええっと|ええと|えっと|あのー+|そのー+|うーんと|うーん|んーと)[、，,]?[ \\t　]*"

    // 区切り（文頭・句読点・空白）の直後にあるときだけフィラーとみなす
    private static let boundaryLookbehind = "(?:^|(?<=[、。，．,.！？!?\\s]))"

    // 「えー」「あー」は「ねえー」「まあー」のような語の一部と区別するため、区切りの直後だけ消す
    private static let shortVowelFillerPattern =
        boundaryLookbehind + "(?:えー+|あー+|んー+|うー+)[、，,]?[ \\t　]*"

    // 「あの」「その」「まあ」「なんか」は「あのファイル」「そのまま」「まあまあ」「なんかの」のように
    // 意味を持つことが多いため、前後とも区切られて独立しているときだけ消す
    private static let ambiguousFillerPattern =
        boundaryLookbehind + "(?:あの|その|まあ|なんか)(?:[、，,][ \\t　]*|[ \\t　]+|$)"

    private static let fillerRegexes: [NSRegularExpression] = [
        unambiguousFillerPattern,
        shortVowelFillerPattern,
        ambiguousFillerPattern,
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.anchorsMatchLines]) }

    private static let maxFillerRemovalPasses = 5

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
        var result = text
        // フィラーが連続すると、前のフィラーを消して初めて次が区切りの直後になるため、変化がなくなるまで繰り返す
        for _ in 0..<Self.maxFillerRemovalPasses {
            let before = result
            for regex in Self.fillerRegexes {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
            }
            if result == before { break }
        }
        return trimDanglingCommas(result)
    }

    private func trimDanglingCommas(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "^[、，, \\t　]+|[、，, \\t　]+$", options: []) else {
            return text
        }
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
