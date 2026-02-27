import Foundation

enum GeminiModel: String, CaseIterable, Codable {
    case gemini25Flash = "gemini-2.5-flash"
    case gemini25FlashLite = "gemini-2.5-flash-lite"
    case gemini20Flash = "gemini-2.0-flash"
    case gemini25Pro = "gemini-2.5-pro"
    case gemini3Flash = "gemini-3-flash"

    var displayName: String {
        switch self {
        case .gemini25Flash:
            return "Gemini 2.5 Flash"
        case .gemini25FlashLite:
            return "Gemini 2.5 Flash Lite"
        case .gemini20Flash:
            return "Gemini 2.0 Flash (廃止予定)"
        case .gemini25Pro:
            return "Gemini 2.5 Pro"
        case .gemini3Flash:
            return "Gemini 3 Flash (Preview)"
        }
    }

    static var defaultModel: GeminiModel { .gemini25Flash }
}
