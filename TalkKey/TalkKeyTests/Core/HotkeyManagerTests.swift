import XCTest
@testable import TalkKey

final class HotkeyManagerTests: XCTestCase {
    private var permissionChecker: MockPermissionCheckerForHotkey!
    private var eventTapProvider: MockEventTapProvider!
    private var manager: HotkeyManager!

    override func setUp() {
        super.setUp()
        permissionChecker = MockPermissionCheckerForHotkey()
        permissionChecker.accessibilityGranted = true
        eventTapProvider = MockEventTapProvider()
        manager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            hotkeyKeyCode: 49
        )
    }

    override func tearDown() {
        manager.stop()
        manager = nil
        eventTapProvider = nil
        permissionChecker = nil
        super.tearDown()
    }

    // MARK: - Key callbacks

    func testKeyDownCallbackIsCalled() throws {
        var keyDownCalled = false
        manager.onKeyDown = { keyDownCalled = true }
        try manager.start()
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        XCTAssertTrue(keyDownCalled)
    }

    func testKeyUpCallbackIsCalled() throws {
        var keyUpCalled = false
        manager.onKeyUp = { keyUpCalled = true }
        try manager.start()
        eventTapProvider.simulateKeyEvent(type: .keyUp, keyCode: 49)
        XCTAssertTrue(keyUpCalled)
    }

    func testNonHotkeyEventsAreIgnored() throws {
        var keyDownCalled = false
        manager.onKeyDown = { keyDownCalled = true }
        try manager.start()
        let consumed = eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 10)
        XCTAssertFalse(keyDownCalled)
        XCTAssertFalse(consumed)
    }

    // MARK: - Start / Stop

    func testStartRegistersHotkey() throws {
        try manager.start()
        XCTAssertTrue(manager.isRunning)
        XCTAssertTrue(eventTapProvider.createCalled)
    }

    func testStopUnregistersHotkey() throws {
        try manager.start()
        manager.stop()
        XCTAssertFalse(manager.isRunning)
        XCTAssertTrue(eventTapProvider.removeCalled)
    }

    func testKeyEventsIgnoredAfterStop() throws {
        var keyDownCalled = false
        manager.onKeyDown = { keyDownCalled = true }
        try manager.start()
        manager.stop()
        // After stop, the callback in provider is nil so nothing happens
        XCTAssertFalse(keyDownCalled)
    }

    // MARK: - Key repeat suppression

    func testKeyDownRepeatIsIgnored() throws {
        var keyDownCount = 0
        manager.onKeyDown = { keyDownCount += 1 }
        try manager.start()
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        XCTAssertEqual(keyDownCount, 1)
    }

    func testKeyUpAfterRepeatCallsOnce() throws {
        var keyUpCount = 0
        manager.onKeyUp = { keyUpCount += 1 }
        try manager.start()
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        eventTapProvider.simulateKeyEvent(type: .keyUp, keyCode: 49)
        XCTAssertEqual(keyUpCount, 1)
    }

    func testKeyDownFiresAgainAfterKeyUp() throws {
        var keyDownCount = 0
        manager.onKeyDown = { keyDownCount += 1 }
        try manager.start()
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        eventTapProvider.simulateKeyEvent(type: .keyUp, keyCode: 49)
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        XCTAssertEqual(keyDownCount, 2)
    }

    // MARK: - Hotkey update

    func testUpdateHotkeyChangesCurrentHotkeyCode() throws {
        XCTAssertEqual(manager.currentHotkeyCode, 49)
        try manager.updateHotkey(keyCode: 48)
        XCTAssertEqual(manager.currentHotkeyCode, 48)
    }

    func testOldKeyIsIgnoredAfterUpdate() throws {
        var keyDownCalled = false
        manager.onKeyDown = { keyDownCalled = true }
        try manager.start()
        try manager.updateHotkey(keyCode: 48)
        let consumed = eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        XCTAssertFalse(keyDownCalled)
        XCTAssertFalse(consumed)
    }

    func testNewKeyFiresCallbacksAfterUpdate() throws {
        var keyDownCalled = false
        var keyUpCalled = false
        manager.onKeyDown = { keyDownCalled = true }
        manager.onKeyUp = { keyUpCalled = true }
        try manager.start()
        try manager.updateHotkey(keyCode: 48)
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 48)
        XCTAssertTrue(keyDownCalled)
        eventTapProvider.simulateKeyEvent(type: .keyUp, keyCode: 48)
        XCTAssertTrue(keyUpCalled)
    }

    func testUpdateHotkeyDoesNotRecreateEventTap() throws {
        try manager.start()
        XCTAssertTrue(manager.isRunning)
        let createCountBefore = eventTapProvider.createCount
        let removeCountBefore = eventTapProvider.removeCount
        try manager.updateHotkey(keyCode: 48)
        XCTAssertTrue(manager.isRunning, "isRunning should remain true after hotkey update")
        XCTAssertEqual(eventTapProvider.createCount, createCountBefore, "Event tap should not be recreated")
        XCTAssertEqual(eventTapProvider.removeCount, removeCountBefore, "Event tap should not be removed")
    }

    func testUpdateHotkeyResetsIsKeyHeld() throws {
        var keyDownCount = 0
        manager.onKeyDown = { keyDownCount += 1 }
        try manager.start()
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        XCTAssertEqual(keyDownCount, 1)
        // isKeyHeld is now true; updating hotkey should reset it
        try manager.updateHotkey(keyCode: 48)
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 48)
        XCTAssertEqual(keyDownCount, 2, "keyDown should fire again after hotkey update resets isKeyHeld")
    }

    // MARK: - Hotkey validation

    func testUpdateHotkeyRejectsCapsLock() {
        XCTAssertThrowsError(try manager.updateHotkey(keyCode: 57),
                             "Caps Lock should be rejected") { error in
            guard let tkError = error as? TalkKeyError,
                  case .invalidHotkey(let code) = tkError else {
                XCTFail("Expected TalkKeyError.invalidHotkey for Caps Lock")
                return
            }
            XCTAssertEqual(code, 57)
        }
    }

    func testUpdateHotkeyAcceptsModifierKeysExceptCapsLock() throws {
        let allowedModifiers: [CGKeyCode] = [54, 55, 56, 58, 59, 60, 61, 62, 63]
        for keyCode in allowedModifiers {
            try manager.updateHotkey(keyCode: keyCode)
            XCTAssertEqual(manager.currentHotkeyCode, keyCode)
        }
    }

    func testUpdateHotkeyAcceptsValidKeys() throws {
        let validKeyCodes: [CGKeyCode] = [49, 48, 36, 0, 1, 12]  // Space, Tab, Return, A, S, Q
        for keyCode in validKeyCodes {
            try manager.updateHotkey(keyCode: keyCode)
            XCTAssertEqual(manager.currentHotkeyCode, keyCode)
        }
    }

    func testUpdateHotkeySingleKeyAllowsOptionKey() throws {
        try manager.updateHotkey(keyCode: 58) // Left Option
        XCTAssertEqual(manager.currentHotkeyCode, 58, "Option should be allowed as single-key hotkey")
    }

    func testUpdateHotkeySingleKeyRejectsCapsLock() {
        XCTAssertThrowsError(try manager.updateHotkey(keyCode: 57)) { error in
            guard let tkError = error as? TalkKeyError,
                  case .invalidHotkey(let code) = tkError else {
                XCTFail("Expected TalkKeyError.invalidHotkey")
                return
            }
            XCTAssertEqual(code, 57)
        }
    }

    // MARK: - Combo mode

    func testComboModeModifierAloneDoesNothing() throws {
        let comboManager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            combo: HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 48)
        )
        var keyDownCalled = false
        comboManager.onKeyDown = { keyDownCalled = true }
        try comboManager.start()
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        XCTAssertFalse(keyDownCalled, "Modifier alone should not trigger onKeyDown")
        comboManager.stop()
    }

    func testComboModeTriggerAloneDoesNothing() throws {
        let comboManager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            combo: HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 48)
        )
        var keyDownCalled = false
        comboManager.onKeyDown = { keyDownCalled = true }
        try comboManager.start()
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 48)
        XCTAssertFalse(keyDownCalled, "Trigger alone should not trigger onKeyDown")
        comboManager.stop()
    }

    func testComboModeModifierThenTriggerActivates() throws {
        let comboManager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            combo: HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 48)
        )
        var keyDownCalled = false
        comboManager.onKeyDown = { keyDownCalled = true }
        try comboManager.start()
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49) // modifier down
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 48) // trigger down
        XCTAssertTrue(keyDownCalled, "Modifier + Trigger should trigger onKeyDown")
        comboManager.stop()
    }

    func testComboModeTriggerReleaseCallsKeyUp() throws {
        let comboManager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            combo: HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 48)
        )
        var keyUpCalled = false
        comboManager.onKeyUp = { keyUpCalled = true }
        try comboManager.start()
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49) // modifier down
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 48) // trigger down
        eventTapProvider.simulateKeyEvent(type: .keyUp, keyCode: 48)   // trigger up
        XCTAssertTrue(keyUpCalled, "Trigger release should call onKeyUp")
        comboManager.stop()
    }

    func testComboModeModifierReleaseWhileActiveSafeStop() throws {
        let comboManager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            combo: HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 48)
        )
        var keyUpCalled = false
        comboManager.onKeyUp = { keyUpCalled = true }
        try comboManager.start()
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49) // modifier down
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 48) // trigger down
        eventTapProvider.simulateKeyEvent(type: .keyUp, keyCode: 49)   // modifier up (safety stop)
        XCTAssertTrue(keyUpCalled, "Modifier release while active should call onKeyUp (safety stop)")
        comboManager.stop()
    }

    func testComboModeKeyRepeatSuppression() throws {
        let comboManager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            combo: HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 48)
        )
        var keyDownCount = 0
        comboManager.onKeyDown = { keyDownCount += 1 }
        try comboManager.start()
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49) // modifier down
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 48) // trigger down
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 48) // trigger repeat
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 48) // trigger repeat
        XCTAssertEqual(keyDownCount, 1, "Trigger repeat should be suppressed")
        comboManager.stop()
    }

    func testSingleKeyModeStillWorks() throws {
        let singleManager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            combo: HotkeyCombo(modifierKeyCode: nil, triggerKeyCode: 49)
        )
        var keyDownCalled = false
        var keyUpCalled = false
        singleManager.onKeyDown = { keyDownCalled = true }
        singleManager.onKeyUp = { keyUpCalled = true }
        try singleManager.start()
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        XCTAssertTrue(keyDownCalled)
        eventTapProvider.simulateKeyEvent(type: .keyUp, keyCode: 49)
        XCTAssertTrue(keyUpCalled)
        singleManager.stop()
    }

    func testUpdateHotkeyWithCombo() throws {
        let comboManager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            combo: HotkeyCombo(modifierKeyCode: nil, triggerKeyCode: 49)
        )
        try comboManager.start()
        let newCombo = HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 48)
        try comboManager.updateHotkey(combo: newCombo)
        XCTAssertEqual(comboManager.currentCombo, newCombo)

        var keyDownCalled = false
        comboManager.onKeyDown = { keyDownCalled = true }
        // Old single-key should not work
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        XCTAssertFalse(keyDownCalled, "Old trigger should not work after combo update")
        // New combo should work
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49) // now modifier
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 48) // trigger
        XCTAssertTrue(keyDownCalled, "New combo should work after update")
        comboManager.stop()
    }

    func testUpdateHotkeyComboAllowsFnAsModifier() throws {
        let fnCombo = HotkeyCombo(modifierKeyCode: 63, triggerKeyCode: 49)
        try manager.updateHotkey(combo: fnCombo)
        XCTAssertEqual(manager.currentCombo, fnCombo, "Fn should be allowed as combo modifier")
    }

    func testUpdateHotkeyComboAllowsModifierKeyAsTriggerInComboMode() throws {
        // Command (55) should be allowed as trigger when a different modifier is set
        let fnCommandCombo = HotkeyCombo(modifierKeyCode: 63, triggerKeyCode: 55)
        try manager.updateHotkey(combo: fnCommandCombo)
        XCTAssertEqual(manager.currentCombo, fnCommandCombo, "Command should be allowed as trigger in combo mode")
    }

    func testUpdateHotkeyComboRejectsSameModifierAndTrigger() {
        let sameKeyCombo = HotkeyCombo(modifierKeyCode: 49, triggerKeyCode: 49)
        XCTAssertThrowsError(try manager.updateHotkey(combo: sameKeyCombo)) { error in
            guard let tkError = error as? TalkKeyError,
                  case .invalidHotkeyCombo = tkError else {
                XCTFail("Expected TalkKeyError.invalidHotkeyCombo")
                return
            }
        }
    }

    func testFnCommandComboWorks() throws {
        let comboManager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            combo: HotkeyCombo(modifierKeyCode: 63, triggerKeyCode: 55)
        )
        var keyDownCalled = false
        var keyUpCalled = false
        comboManager.onKeyDown = { keyDownCalled = true }
        comboManager.onKeyUp = { keyUpCalled = true }
        try comboManager.start()

        // Fn down
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 63)
        XCTAssertFalse(keyDownCalled, "Fn alone should not trigger")

        // Command down while Fn held
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 55)
        XCTAssertTrue(keyDownCalled, "Fn + Command should trigger onKeyDown")

        // Command up
        eventTapProvider.simulateKeyEvent(type: .keyUp, keyCode: 55)
        XCTAssertTrue(keyUpCalled, "Command release should trigger onKeyUp")

        comboManager.stop()
    }

    func testFnSpaceComboWorks() throws {
        let comboManager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            combo: HotkeyCombo(modifierKeyCode: 63, triggerKeyCode: 49)
        )
        var keyDownCalled = false
        var keyUpCalled = false
        comboManager.onKeyDown = { keyDownCalled = true }
        comboManager.onKeyUp = { keyUpCalled = true }
        try comboManager.start()

        // Fn down (simulated as keyDown by SystemEventTapProvider translation)
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 63)
        XCTAssertFalse(keyDownCalled, "Fn alone should not trigger")

        // Space down while Fn held
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        XCTAssertTrue(keyDownCalled, "Fn + Space should trigger onKeyDown")

        // Space up
        eventTapProvider.simulateKeyEvent(type: .keyUp, keyCode: 49)
        XCTAssertTrue(keyUpCalled, "Space release should trigger onKeyUp")

        comboManager.stop()
    }

    // MARK: - Accessibility permission

    func testStartThrowsWhenEventTapCreationFails() {
        eventTapProvider.shouldFailCreate = true
        XCTAssertThrowsError(try manager.start()) { error in
            guard let tkError = error as? TalkKeyError else {
                XCTFail("Expected TalkKeyError")
                return
            }
            if case .permissionDenied(let detail) = tkError {
                XCTAssertTrue(detail.contains("Accessibility"))
            } else {
                XCTFail("Expected permissionDenied error")
            }
        }
    }

    // MARK: - Missed key-up detection

    func testReleaseCheckFiresKeyUpWhenKeyIsNoLongerHeld() throws {
        let keyState = MockKeyStateProvider()
        let checkedManager = HotkeyManager(eventTapProvider: eventTapProvider, combo: HotkeyCombo(modifierKeyCode: nil, triggerKeyCode: 56), keyStateProvider: keyState)
        var keyUpCount = 0
        checkedManager.onKeyUp = { keyUpCount += 1 }
        try checkedManager.start()

        keyState.heldKeys = [56]
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 56)
        checkedManager.releaseIfKeysNotHeld()
        XCTAssertEqual(keyUpCount, 0, "Key is still held")

        // 離した通知を取りこぼした
        keyState.heldKeys = []
        checkedManager.releaseIfKeysNotHeld()
        XCTAssertEqual(keyUpCount, 1)
        checkedManager.releaseIfKeysNotHeld()
        XCTAssertEqual(keyUpCount, 1, "Should fire only once")
        checkedManager.stop()
    }

    func testReleaseCheckDoesNothingWhenNotPressed() throws {
        let keyState = MockKeyStateProvider()
        let checkedManager = HotkeyManager(eventTapProvider: eventTapProvider, combo: HotkeyCombo(modifierKeyCode: nil, triggerKeyCode: 56), keyStateProvider: keyState)
        var keyUpCalled = false
        checkedManager.onKeyUp = { keyUpCalled = true }
        try checkedManager.start()
        checkedManager.releaseIfKeysNotHeld()
        XCTAssertFalse(keyUpCalled)
        checkedManager.stop()
    }

    func testReleaseCheckAllowsPressingAgainAfterMissedKeyUp() throws {
        let keyState = MockKeyStateProvider()
        let checkedManager = HotkeyManager(eventTapProvider: eventTapProvider, combo: HotkeyCombo(modifierKeyCode: nil, triggerKeyCode: 56), keyStateProvider: keyState)
        var keyDownCount = 0
        checkedManager.onKeyDown = { keyDownCount += 1 }
        try checkedManager.start()

        keyState.heldKeys = [56]
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 56)
        keyState.heldKeys = []
        checkedManager.releaseIfKeysNotHeld()
        keyState.heldKeys = [56]
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 56)
        XCTAssertEqual(keyDownCount, 2)
        checkedManager.stop()
    }

    func testReleaseCheckInComboModeFiresKeyUpWhenTriggerIsNoLongerHeld() throws {
        let keyState = MockKeyStateProvider()
        let checkedManager = HotkeyManager(eventTapProvider: eventTapProvider, combo: HotkeyCombo(modifierKeyCode: 58, triggerKeyCode: 49), keyStateProvider: keyState)
        var keyUpCount = 0
        var keyDownCount = 0
        checkedManager.onKeyUp = { keyUpCount += 1 }
        checkedManager.onKeyDown = { keyDownCount += 1 }
        try checkedManager.start()

        keyState.heldKeys = [58, 49]
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 58)
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        checkedManager.releaseIfKeysNotHeld()
        XCTAssertEqual(keyUpCount, 0)

        keyState.heldKeys = [58]
        checkedManager.releaseIfKeysNotHeld()
        XCTAssertEqual(keyUpCount, 1)

        // 修飾キーは押したままなので、トリガーを押し直せばまた始まる
        keyState.heldKeys = [58, 49]
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 49)
        XCTAssertEqual(keyDownCount, 2)
        checkedManager.stop()
    }

    func testReleaseCheckRunsPeriodicallyWhileKeyIsHeld() throws {
        let keyState = MockKeyStateProvider()
        let checkedManager = HotkeyManager(
            eventTapProvider: eventTapProvider,
            combo: HotkeyCombo(modifierKeyCode: nil, triggerKeyCode: 56),
            keyStateProvider: keyState,
            releaseCheckInterval: 0.05
        )
        let keyUp = expectation(description: "missed key-up is detected")
        checkedManager.onKeyUp = { keyUp.fulfill() }
        try checkedManager.start()

        keyState.heldKeys = [56]
        eventTapProvider.simulateKeyEvent(type: .keyDown, keyCode: 56)
        keyState.heldKeys = []
        wait(for: [keyUp], timeout: 1.0)
        checkedManager.stop()
    }
}

// MARK: - Mocks

final class MockKeyStateProvider: KeyStateProviderProtocol {
    var heldKeys: Set<CGKeyCode> = []

    func isKeyDown(_ keyCode: CGKeyCode) -> Bool {
        heldKeys.contains(keyCode)
    }
}

private final class MockPermissionCheckerForHotkey: PermissionCheckerProtocol {
    var accessibilityGranted = true

    func checkMicrophonePermission() -> PermissionStatus { .authorized }
    func checkSpeechRecognitionPermission() -> PermissionStatus { .authorized }
    func checkAccessibilityPermission() -> Bool { accessibilityGranted }
    func requestAccessibilityAccess() -> Bool { accessibilityGranted }
    func requestMicrophoneAccess() async -> Bool { true }
    func requestSpeechRecognitionAccess() async -> Bool { true }
}

final class MockEventTapProvider: EventTapProviderProtocol {
    private(set) var createCalled = false
    private(set) var removeCalled = false
    private(set) var createCount = 0
    private(set) var removeCount = 0
    var shouldFailCreate = false
    private var callback: ((CGEventType, CGKeyCode) -> Bool)?

    func createEventTap(callback: @escaping (CGEventType, CGKeyCode) -> Bool) throws {
        if shouldFailCreate {
            throw TalkKeyError.permissionDenied("Failed to create event tap")
        }
        createCalled = true
        createCount += 1
        self.callback = callback
    }

    func removeEventTap() {
        removeCalled = true
        removeCount += 1
        callback = nil
    }

    @discardableResult
    func simulateKeyEvent(type: CGEventType, keyCode: CGKeyCode) -> Bool {
        return callback?(type, keyCode) ?? false
    }
}
