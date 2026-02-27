import Foundation
import Carbon

struct HotkeyCombo: Codable, Equatable {
    let modifierKeyCode: CGKeyCode?
    let triggerKeyCode: CGKeyCode

    var isSingleKey: Bool { modifierKeyCode == nil }

    static let `default` = HotkeyCombo(modifierKeyCode: nil, triggerKeyCode: 58)
}
