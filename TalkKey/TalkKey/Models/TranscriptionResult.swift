import Foundation

struct TranscriptionResult: Codable, Equatable {
    let rawText: String
    let formattedText: String?
    let timestamp: Date
    let duration: TimeInterval
    // 履歴の保存形式と互換を保つため任意項目にする（古い履歴には無い）
    var engine: RecognitionSource? = nil
}
