import Foundation

enum GeminiModel: String, CaseIterable, Codable {
    case gemini38Flash = "gemini-3.8-flash"
    case gemini35FlashLite = "gemini-3.5-flash-lite"
    case geminiFlashLatest = "gemini-flash-latest"
    case geminiFlashLiteLatest = "gemini-flash-lite-latest"

    var displayName: String {
        switch self {
        case .gemini38Flash:
            return "Gemini 3.8 Flash"
        case .gemini35FlashLite:
            return "Gemini 3.5 Flash Lite (軽量)"
        case .geminiFlashLatest:
            return "Gemini Flash (最新版)"
        case .geminiFlashLiteLatest:
            return "Gemini Flash Lite (最新版)"
        }
    }

    static var defaultModel: GeminiModel { .gemini38Flash }

    /// UserDefaults に保存された値から復元する。廃止済みのモデル（2.x など）や不明な値は既定のモデルに移す
    init(storedValue: String?) {
        self = storedValue.flatMap(GeminiModel.init(rawValue:)) ?? .defaultModel
    }
}
