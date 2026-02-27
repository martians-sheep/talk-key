import XCTest
@testable import TalkKey

final class HotkeyComboTests: XCTestCase {
    // MARK: - Default and single-key

    func testDefaultComboIsOptionSingleKey() {
        let combo = HotkeyCombo.default
        XCTAssertNil(combo.modifierKeyCode, "Default should be single-key (no modifier)")
        XCTAssertEqual(combo.triggerKeyCode, 58, "Default trigger should be Option (58)")
        XCTAssertTrue(combo.isSingleKey)
    }

    func testSingleKeyComboHasNilModifier() {
        let combo = HotkeyCombo(modifierKeyCode: nil, triggerKeyCode: 49)
        XCTAssertNil(combo.modifierKeyCode)
        XCTAssertTrue(combo.isSingleKey)
    }

    // MARK: - Codable and Equatable

    func testCodableRoundTrip() throws {
        let original = HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 48)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyCombo.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testCodableRoundTripSingleKey() throws {
        let original = HotkeyCombo(modifierKeyCode: nil, triggerKeyCode: 36)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyCombo.self, from: data)
        XCTAssertEqual(original, decoded)
        XCTAssertNil(decoded.modifierKeyCode)
    }

    func testEquatable() {
        let a = HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 48)
        let b = HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 48)
        let c = HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 36)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
