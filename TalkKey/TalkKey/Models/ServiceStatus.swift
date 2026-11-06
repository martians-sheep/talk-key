import Foundation

enum ServiceStatus: Equatable {
    case idle
    case recording
    case processing
    case inserting
    case error(String)

    /// エラーのあとも次の録音は受け付ける（エラーで止まったままにしない）
    var canStartRecording: Bool {
        switch self {
        case .idle, .error: return true
        case .recording, .processing, .inserting: return false
        }
    }
}
