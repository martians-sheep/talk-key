import XCTest
@testable import TalkKey

final class HotkeySettingsStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var store: HotkeySettingsStore!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: "com.talkkey.test.hotkeySettings")!
        userDefaults.removePersistentDomain(forName: "com.talkkey.test.hotkeySettings")
        store = HotkeySettingsStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: "com.talkkey.test.hotkeySettings")
        userDefaults = nil
        store = nil
        super.tearDown()
    }

    func testSaveAndLoadReturnsSameValue() {
        store.save(keyCode: 48)
        XCTAssertEqual(store.load(), 48)
    }

    func testLoadReturnsDefaultWhenNotSet() {
        XCTAssertEqual(store.load(), 49)
    }

    func testLoadFallsBackToDefaultForBlockedKeyCode() {
        // Directly write a blocked keyCode (Caps Lock = 57) to UserDefaults
        userDefaults.set(57, forKey: "hotkeyKeyCode")
        XCTAssertEqual(store.load(), 49, "Blocked keyCode should fall back to default")
    }

    // MARK: - Combo persistence

    func testSaveAndLoadCombo() throws {
        let combo = HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 48)
        store.save(combo: combo)
        let loaded = store.loadCombo()
        XCTAssertEqual(loaded, combo)
    }

    func testLoadComboDefaultWhenEmpty() {
        let loaded = store.loadCombo()
        XCTAssertEqual(loaded, .default, "Should return Option default when nothing is saved")
    }

    func testMigrationFromOldSingleKeyFormat() {
        // Simulate old format: single Int keyCode
        userDefaults.set(36, forKey: "hotkeyKeyCode")
        let loaded = store.loadCombo()
        XCTAssertEqual(loaded.modifierKeyCode, nil, "Migrated combo should be single-key")
        XCTAssertEqual(loaded.triggerKeyCode, 36, "Migrated combo should use the old keyCode as trigger")
    }

    func testMigrationDeletesOldKey() {
        userDefaults.set(36, forKey: "hotkeyKeyCode")
        _ = store.loadCombo()
        XCTAssertEqual(userDefaults.integer(forKey: "hotkeyKeyCode"), 0, "Old key should be removed after migration")
    }
}
