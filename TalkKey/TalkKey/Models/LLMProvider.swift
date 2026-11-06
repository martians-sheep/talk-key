import Foundation

enum LLMProvider: String, CaseIterable, Codable {
    case claude
    case gemini

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .gemini: return "Gemini"
        }
    }

    /// Keychain（service "com.talkkey."）の account 名
    var keychainAccount: String {
        switch self {
        case .claude: return "anthropicApiKey"
        case .gemini: return "apiKey"
        }
    }

    static var defaultProvider: LLMProvider { .claude }

    init(storedValue: String?) {
        self = storedValue.flatMap(LLMProvider.init(rawValue:)) ?? .defaultProvider
    }
}
