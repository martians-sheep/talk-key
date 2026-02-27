import Foundation
import Carbon

final class HotkeySettingsStore: HotkeySettingsStoreProtocol {
    private let userDefaults: UserDefaults
    private let legacyKey = "hotkeyKeyCode"
    private let comboKey = "hotkeyCombo"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Combo API

    func save(combo: HotkeyCombo) {
        if let data = try? JSONEncoder().encode(combo) {
            userDefaults.set(data, forKey: comboKey)
        }
    }

    func loadCombo() -> HotkeyCombo {
        // Try new format first
        if let data = userDefaults.data(forKey: comboKey),
           let combo = try? JSONDecoder().decode(HotkeyCombo.self, from: data) {
            return combo
        }

        // Migrate from old single-key format
        let legacyValue = userDefaults.integer(forKey: legacyKey)
        if legacyValue > 0 {
            let keyCode = CGKeyCode(legacyValue)
            guard !HotkeyManager.blockedSingleKeyCodes.contains(keyCode) else {
                return .default
            }
            let migrated = HotkeyCombo(modifierKeyCode: nil, triggerKeyCode: keyCode)
            save(combo: migrated)
            userDefaults.removeObject(forKey: legacyKey)
            return migrated
        }

        return .default
    }

    // MARK: - Legacy single-key API

    func save(keyCode: CGKeyCode) {
        userDefaults.set(Int(keyCode), forKey: legacyKey)
    }

    func load() -> CGKeyCode {
        let value = userDefaults.integer(forKey: legacyKey)
        guard value > 0 else { return defaultKeyCode }
        let keyCode = CGKeyCode(value)
        guard !HotkeyManager.blockedSingleKeyCodes.contains(keyCode) else {
            return defaultKeyCode
        }
        return keyCode
    }

    private let defaultKeyCode: CGKeyCode = 49
}
