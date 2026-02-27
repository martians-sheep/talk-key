import XCTest
@testable import TalkKey

final class KeyCodeHelperTests: XCTestCase {
    func testSpaceKeyName() {
        XCTAssertEqual(KeyCodeHelper.keyName(for: 49), "Space")
    }

    func testReturnKeyName() {
        XCTAssertEqual(KeyCodeHelper.keyName(for: 36), "Return")
    }

    func testTabKeyName() {
        XCTAssertEqual(KeyCodeHelper.keyName(for: 48), "Tab")
    }

    func testDeleteKeyName() {
        XCTAssertEqual(KeyCodeHelper.keyName(for: 51), "Delete")
    }

    func testEscapeKeyName() {
        XCTAssertEqual(KeyCodeHelper.keyName(for: 53), "Escape")
    }

    func testUnknownKeyCodeFallback() {
        XCTAssertEqual(KeyCodeHelper.keyName(for: 200), "キー(200)")
    }

    func testFnKeyName() {
        XCTAssertEqual(KeyCodeHelper.keyName(for: 63), "Fn")
    }

    // MARK: - Combo name

    func testComboNameWithModifier() {
        let combo = HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 48)
        XCTAssertEqual(KeyCodeHelper.comboName(for: combo), "Space + Tab")
    }

    func testComboNameWithFnModifier() {
        let combo = HotkeyCombo(modifierKeyCode: 63, triggerKeyCode: 49)
        XCTAssertEqual(KeyCodeHelper.comboName(for: combo), "Fn + Space")
    }

    func testComboNameFnCommand() {
        let combo = HotkeyCombo(modifierKeyCode: 63, triggerKeyCode: 55)
        XCTAssertEqual(KeyCodeHelper.comboName(for: combo), "Fn + Command")
    }

    func testComboNameSingleKey() {
        let combo = HotkeyCombo(modifierKeyCode: nil, triggerKeyCode: 49)
        XCTAssertEqual(KeyCodeHelper.comboName(for: combo), "Space")
    }
}
