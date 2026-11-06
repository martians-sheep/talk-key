import Foundation

final class RecognitionSettingsStore: RecognitionSettingsStoreProtocol {
    static let defaultWhisperServerURL = URL(string: "http://127.0.0.1:8178")!

    private enum Keys {
        static let engine = "recognitionEngine"
        static let whisperServerURL = "whisperServerURL"
        static let vocabularyHint = "vocabularyHint"
        static let whisperBinaryPath = "whisperBinaryPath"
        static let whisperModelPath = "whisperModelPath"
        static let whisperVADModelPath = "whisperVADModelPath"
    }

    private let userDefaults: UserDefaults
    private let homeDirectory: String

    init(userDefaults: UserDefaults = .standard, homeDirectory: String = NSHomeDirectory()) {
        self.userDefaults = userDefaults
        self.homeDirectory = homeDirectory
    }

    func load() -> RecognitionSettings {
        RecognitionSettings(
            engine: userDefaults.string(forKey: Keys.engine).flatMap(RecognitionEngine.init(rawValue:))
                ?? .defaultEngine,
            whisperServerURL: loadURL(),
            vocabularyHint: userDefaults.string(forKey: Keys.vocabularyHint) ?? "",
            whisperBinaryPath: loadPath(Keys.whisperBinaryPath, default: ".local/src/whisper.cpp/build/bin/whisper-server"),
            whisperModelPath: loadPath(Keys.whisperModelPath, default: ".local/share/whisper/ggml-large-v3-turbo-q5_0.bin"),
            whisperVADModelPath: loadPath(Keys.whisperVADModelPath, default: ".local/share/whisper/ggml-silero-v6.2.0.bin")
        )
    }

    func save(_ settings: RecognitionSettings) {
        userDefaults.set(settings.engine.rawValue, forKey: Keys.engine)
        userDefaults.set(settings.whisperServerURL.absoluteString, forKey: Keys.whisperServerURL)
        userDefaults.set(settings.vocabularyHint, forKey: Keys.vocabularyHint)
        userDefaults.set(settings.whisperBinaryPath, forKey: Keys.whisperBinaryPath)
        userDefaults.set(settings.whisperModelPath, forKey: Keys.whisperModelPath)
        userDefaults.set(settings.whisperVADModelPath, forKey: Keys.whisperVADModelPath)
    }

    /// 文字列を http(s) の URL として解釈する。解釈できなければ nil
    static func parseServerURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme, ["http", "https"].contains(scheme),
              url.host != nil else { return nil }
        return url
    }

    private func loadURL() -> URL {
        userDefaults.string(forKey: Keys.whisperServerURL).flatMap(Self.parseServerURL) ?? Self.defaultWhisperServerURL
    }

    private func loadPath(_ key: String, default relativePath: String) -> String {
        if let stored = userDefaults.string(forKey: key), !stored.isEmpty {
            return (stored as NSString).expandingTildeInPath
        }
        return (homeDirectory as NSString).appendingPathComponent(relativePath)
    }
}
