import Foundation

struct TranscriptionResult: Codable, Equatable {
    let rawText: String
    let formattedText: String?
    let timestamp: Date
    let duration: TimeInterval
}
