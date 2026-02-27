import Foundation
import Carbon

protocol HotkeySettingsStoreProtocol {
    func save(combo: HotkeyCombo)
    func loadCombo() -> HotkeyCombo
    func save(keyCode: CGKeyCode)
    func load() -> CGKeyCode
}
