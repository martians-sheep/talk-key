import Foundation

/// 設定で選ぶ認識エンジン
enum RecognitionEngine: String, CaseIterable, Codable {
    case whisperWithAppleFallback = "whisper"
    case appleOnly = "apple"

    var displayName: String {
        switch self {
        case .whisperWithAppleFallback: return "whisper.cpp（Apple 認識に自動で切替）"
        case .appleOnly: return "Apple 音声認識のみ"
        }
    }

    static var defaultEngine: RecognitionEngine { .whisperWithAppleFallback }
}
