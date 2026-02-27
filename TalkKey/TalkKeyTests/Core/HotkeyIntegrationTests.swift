import XCTest
@testable import TalkKey

final class HotkeyIntegrationTests: XCTestCase {
    private var eventTapProvider: MockEventTapProvider!
    private var userDefaults: UserDefaults!
    private var store: HotkeySettingsStore!

    override func setUp() {
        super.setUp()
        eventTapProvider = MockEventTapProvider()
        userDefaults = UserDefaults(suiteName: "com.talkkey.test.hotkeyIntegration")!
        userDefaults.removePersistentDomain(forName: "com.talkkey.test.hotkeyIntegration")
        store = HotkeySettingsStore(userDefaults: userDefaults)
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: "com.talkkey.test.hotkeyIntegration")
        userDefaults = nil
        store = nil
        eventTapProvider = nil
        super.tearDown()
    }

    // MARK: - Single-key (legacy)

    func testSavedKeyCodeIsUsedByHotkeyManager() throws {
        store.save(keyCode: 48)
        let loadedKeyCode = store.load()
        let manager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            hotkeyKeyCode: loadedKeyCode
        )
        var keyDownCalled = false
        manager.onKeyDown = { keyDownCalled = true }
        try manager.start()
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 48)
        XCTAssertTrue(keyDownCalled)
        manager.stop()
    }

    func testBlockedKeyCodeRejectedAndCurrentCodeUnchanged() throws {
        let manager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            hotkeyKeyCode: 49
        )
        XCTAssertEqual(manager.currentHotkeyCode, 49)
        XCTAssertThrowsError(try manager.updateHotkey(keyCode: 57), "Caps Lock should be rejected")
        XCTAssertEqual(manager.currentHotkeyCode, 49, "currentHotkeyCode should remain unchanged after rejected update")
    }

    func testConsecutiveUpdatesOnlyLastKeyCodeActive() throws {
        let manager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            hotkeyKeyCode: 49
        )
        var keyDownCount = 0
        manager.onKeyDown = { keyDownCount += 1 }
        try manager.start()

        try manager.updateHotkey(keyCode: 48)
        try manager.updateHotkey(keyCode: 36)
        try manager.updateHotkey(keyCode: 12)

        // Only keyCode 12 should trigger
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 48)
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 36)
        XCTAssertEqual(keyDownCount, 0, "Previous keyCodes should be ignored")

        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 12)
        XCTAssertEqual(keyDownCount, 1, "Only the last keyCode should trigger")
        XCTAssertEqual(manager.currentHotkeyCode, 12)

        manager.stop()
    }

    // MARK: - Combo mode

    func testSavedComboIsUsedByHotkeyManager() throws {
        let combo = HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 48)
        store.save(combo: combo)
        let loadedCombo = store.loadCombo()
        let manager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            combo: loadedCombo
        )
        var keyDownCalled = false
        manager.onKeyDown = { keyDownCalled = true }
        try manager.start()

        // Trigger alone should not work
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 48)
        XCTAssertFalse(keyDownCalled, "Trigger alone should not activate")

        // Modifier + Trigger should work
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49) // modifier
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 48) // trigger
        XCTAssertTrue(keyDownCalled, "Combo should activate")
        manager.stop()
    }

    func testComboModeSafeStopOnModifierRelease() throws {
        let combo = HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 48)
        let manager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            combo: combo
        )
        var keyUpCalled = false
        manager.onKeyUp = { keyUpCalled = true }
        try manager.start()

        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49) // modifier down
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 48) // trigger down
        eventTapProvider.simulateKeyEvent(type: .keyUp, keyCode: 49)   // modifier up (safety stop)
        XCTAssertTrue(keyUpCalled, "Releasing modifier while active should safety-stop")
        manager.stop()
    }

    func testMigrationFlowSingleKeyToCombo() throws {
        // Simulate old format
        userDefaults.set(36, forKey: "hotkeyKeyCode")

        // Load should migrate
        let loadedCombo = store.loadCombo()
        XCTAssertNil(loadedCombo.modifierKeyCode, "Migrated combo should be single-key")
        XCTAssertEqual(loadedCombo.triggerKeyCode, 36)

        // Manager should work with migrated combo
        let manager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            combo: loadedCombo
        )
        var keyDownCalled = false
        manager.onKeyDown = { keyDownCalled = true }
        try manager.start()
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 36)
        XCTAssertTrue(keyDownCalled)

        // Old key should be removed
        XCTAssertEqual(userDefaults.integer(forKey: "hotkeyKeyCode"), 0)
        manager.stop()
    }
}
