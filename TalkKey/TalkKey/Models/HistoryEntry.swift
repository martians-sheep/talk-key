import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let result: TranscriptionResult
    let mode: FormattingMode
    let createdAt: Date
}
