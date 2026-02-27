import Foundation
import Carbon

protocol HotkeyManagerProtocol: AnyObject {
    var onKeyDown: (() -> Void)? { get set }
    var onKeyUp: (() -> Void)? { get set }
    var currentCombo: HotkeyCombo { get }
    var currentHotkeyCode: CGKeyCode { get }
    func start() throws
    func stop()
    func updateHotkey(combo: HotkeyCombo) throws
    func updateHotkey(keyCode: CGKeyCode) throws
}
