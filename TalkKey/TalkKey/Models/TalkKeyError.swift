import Foundation
import Carbon

enum TalkKeyError: LocalizedError {
    case alreadyRecording
    case notRecording
    case permissionDenied(String)
    case transcriptionFailed(String)
    case insertionFailed(String)
    case formattingFailed(String)
    case invalidHotkey(CGKeyCode)
    case invalidHotkeyCombo(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording: return "Already recording"
        case .notRecording: return "Not currently recording"
        case .permissionDenied(let detail): return "Permission denied: \(detail)"
        case .transcriptionFailed(let detail): return "Transcription failed: \(detail)"
        case .insertionFailed(let detail): return "Insertion failed: \(detail)"
        case .formattingFailed(let detail): return "Formatting failed: \(detail)"
        case .invalidHotkey(let keyCode): return "Invalid hotkey: keyCode \(keyCode) is a modifier key"
        case .invalidHotkeyCombo(let detail): return "Invalid hotkey combo: \(detail)"
        }
    }
}
