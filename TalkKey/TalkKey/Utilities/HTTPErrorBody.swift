import Foundation

enum HTTPErrorBody {
    /// ログ用に応答本文の先頭を取り出す。万一キーが含まれていても伏せる
    static func prefix(of data: Data, limit: Int, redacting secret: String) -> String {
        let text = String(decoding: data.prefix(limit * 4), as: UTF8.self)
        let redacted = secret.isEmpty ? text : text.replacingOccurrences(of: secret, with: "***")
        return String(redacted.prefix(limit)).replacingOccurrences(of: "\n", with: " ")
    }
}
