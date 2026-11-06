import Foundation
import Carbon

protocol EventTapProviderProtocol: AnyObject {
    func createEventTap(callback: @escaping (CGEventType, CGKeyCode) -> Bool) throws
    func removeEventTap()
}

protocol KeyStateProviderProtocol: AnyObject {
    func isKeyDown(_ keyCode: CGKeyCode) -> Bool
}

final class HotkeyManager: HotkeyManagerProtocol {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    private let eventTapProvider: EventTapProviderProtocol
    private let keyStateProvider: KeyStateProviderProtocol
    private let releaseCheckInterval: TimeInterval
    private let logger: LoggerProtocol
    private var releaseCheckTimer: Timer?
    private(set) var isRunning = false
    private(set) var combo: HotkeyCombo

    // Single-key state
    private var isKeyHeld = false

    // Combo state
    private var isModifierHeld = false
    private var isTriggerHeld = false
    private var isActivated = false

    /// Key codes that are blocked as single-key hotkeys due to unreliable press/release detection.
    /// Caps Lock uses toggle behavior (not hold), making it unsuitable for Push-to-talk.
    /// Other modifier keys (Command, Shift, Option, Control, Fn) work fine for hold-to-talk.
    static let blockedSingleKeyCodes: Set<CGKeyCode> = [
        57, // Caps Lock (toggle behavior, not hold)
    ]

    /// All OS modifier key codes (used for flagsChanged event identification).
    static let modifierKeyCodes: Set<CGKeyCode> = [
        54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
    ]

    init(
        eventTapProvider: EventTapProviderProtocol = SystemEventTapProvider(),
        combo: HotkeyCombo = .default,
        keyStateProvider: KeyStateProviderProtocol = SystemKeyStateProvider(),
        releaseCheckInterval: TimeInterval = 0.5,
        logger: LoggerProtocol = FileLogger.shared
    ) {
        self.eventTapProvider = eventTapProvider
        self.combo = combo
        self.keyStateProvider = keyStateProvider
        self.releaseCheckInterval = releaseCheckInterval
        self.logger = logger
    }

    deinit {
        releaseCheckTimer?.invalidate()
    }

    convenience init(
        eventTapProvider: EventTapProviderProtocol = SystemEventTapProvider(),
        hotkeyKeyCode: CGKeyCode = 49,
        logger: LoggerProtocol = FileLogger.shared
    ) {
        self.init(
            eventTapProvider: eventTapProvider,
            combo: HotkeyCombo(modifierKeyCode: nil, triggerKeyCode: hotkeyKeyCode),
            logger: logger
        )
    }

    var currentCombo: HotkeyCombo { combo }

    var currentHotkeyCode: CGKeyCode { combo.triggerKeyCode }

    func updateHotkey(combo: HotkeyCombo) throws {
        // Caps Lock is always blocked (toggle behavior incompatible with push-to-talk)
        if Self.blockedSingleKeyCodes.contains(combo.triggerKeyCode) {
            throw TalkKeyError.invalidHotkey(combo.triggerKeyCode)
        }
        // Combo mode: modifier and trigger must be different
        if let modifier = combo.modifierKeyCode, modifier == combo.triggerKeyCode {
            throw TalkKeyError.invalidHotkeyCombo("修飾キーとトリガーキーが同じです")
        }
        self.combo = combo
        resetState()
    }

    func updateHotkey(keyCode: CGKeyCode) throws {
        try updateHotkey(combo: HotkeyCombo(modifierKeyCode: nil, triggerKeyCode: keyCode))
    }

    func start() throws {
        guard !isRunning else { return }

        do {
            try eventTapProvider.createEventTap { [weak self] eventType, keyCode in
                guard let self = self else { return false }
                return self.handleKeyEvent(type: eventType, keyCode: keyCode)
            }
            isRunning = true
            logger.info("Hotkey manager started")
        } catch {
            logger.error("Hotkey manager failed to start")
            throw TalkKeyError.permissionDenied("Accessibility permission is required for global hotkeys")
        }
    }

    func stop() {
        guard isRunning else { return }
        stopReleaseCheck()
        eventTapProvider.removeEventTap()
        isRunning = false
        logger.debug("Hotkey manager stopped")
    }

    /// 離した通知を取りこぼすと録音が止まらないため、押している間は実際のキーの状態も確かめる
    func releaseIfKeysNotHeld() {
        if combo.isSingleKey {
            guard isKeyHeld, !keyStateProvider.isKeyDown(combo.triggerKeyCode) else { return }
            isKeyHeld = false
        } else {
            guard isActivated else { return }
            let isModifierDown = combo.modifierKeyCode.map(keyStateProvider.isKeyDown) ?? false
            guard !(isModifierDown && keyStateProvider.isKeyDown(combo.triggerKeyCode)) else { return }
            isActivated = false
            isTriggerHeld = false
            isModifierHeld = isModifierDown
        }
        stopReleaseCheck()
        logger.warning("Hotkey release was missed; treating it as released")
        onKeyUp?()
    }

    private func startReleaseCheck() {
        releaseCheckTimer?.invalidate()
        releaseCheckTimer = Timer.scheduledTimer(withTimeInterval: releaseCheckInterval, repeats: true) { [weak self] _ in
            self?.releaseIfKeysNotHeld()
        }
    }

    private func stopReleaseCheck() {
        releaseCheckTimer?.invalidate()
        releaseCheckTimer = nil
    }

    private func resetState() {
        stopReleaseCheck()
        isKeyHeld = false
        isModifierHeld = false
        isTriggerHeld = false
        isActivated = false
    }

    private func handleKeyEvent(type: CGEventType, keyCode: CGKeyCode) -> Bool {
        if combo.isSingleKey {
            return handleSingleKeyEvent(type: type, keyCode: keyCode)
        } else {
            return handleComboEvent(type: type, keyCode: keyCode)
        }
    }

    // MARK: - Single-key mode

    private func handleSingleKeyEvent(type: CGEventType, keyCode: CGKeyCode) -> Bool {
        guard keyCode == combo.triggerKeyCode else { return false }
        switch type {
        case .keyDown:
            guard !isKeyHeld else { return true }
            isKeyHeld = true
            startReleaseCheck()
            onKeyDown?()
            return true
        case .keyUp:
            isKeyHeld = false
            stopReleaseCheck()
            onKeyUp?()
            return true
        default:
            return false
        }
    }

    // MARK: - Combo mode

    private func handleComboEvent(type: CGEventType, keyCode: CGKeyCode) -> Bool {
        guard let modifierCode = combo.modifierKeyCode else { return false }
        let triggerCode = combo.triggerKeyCode

        if keyCode == modifierCode {
            return handleModifierEvent(type: type)
        } else if keyCode == triggerCode {
            return handleTriggerEvent(type: type)
        }
        return false
    }

    private func handleModifierEvent(type: CGEventType) -> Bool {
        switch type {
        case .keyDown:
            isModifierHeld = true
            return true
        case .keyUp:
            isModifierHeld = false
            if isActivated {
                // Safety stop: modifier released while recording
                isActivated = false
                isTriggerHeld = false
                stopReleaseCheck()
                onKeyUp?()
            }
            return true
        default:
            return false
        }
    }

    private func handleTriggerEvent(type: CGEventType) -> Bool {
        switch type {
        case .keyDown:
            guard isModifierHeld else { return false }
            guard !isTriggerHeld else { return true } // repeat suppression
            isTriggerHeld = true
            isActivated = true
            startReleaseCheck()
            onKeyDown?()
            return true
        case .keyUp:
            guard isTriggerHeld else { return false }
            isTriggerHeld = false
            if isActivated {
                isActivated = false
                stopReleaseCheck()
                onKeyUp?()
            }
            return true
        default:
            return false
        }
    }
}

final class SystemEventTapProvider: EventTapProviderProtocol {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var callback: ((CGEventType, CGKeyCode) -> Bool)?

    private static let modifierFlagMap: [CGKeyCode: CGEventFlags] = [
        54: .maskCommand,      // Right Command
        55: .maskCommand,      // Left Command
        56: .maskShift,        // Left Shift
        57: .maskAlphaShift,   // Caps Lock
        58: .maskAlternate,    // Left Option
        59: .maskControl,      // Left Control
        60: .maskShift,        // Right Shift
        61: .maskAlternate,    // Right Option
        62: .maskControl,      // Right Control
        63: .maskSecondaryFn,  // Fn (Globe)
    ]

    static func syntheticTypeForFlagsChanged(keyCode: CGKeyCode, flags: CGEventFlags) -> CGEventType {
        guard let expectedFlag = modifierFlagMap[keyCode] else { return .flagsChanged }
        return flags.contains(expectedFlag) ? .keyDown : .keyUp
    }

    func createEventTap(callback: @escaping (CGEventType, CGKeyCode) -> Bool) throws {
        self.callback = callback
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let tapCallback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let provider = Unmanaged<SystemEventTapProvider>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                // 止まっていた間のキー操作は届かない。離した操作の取りこぼしは releaseIfKeysNotHeld で拾う
                FileLogger.shared.warning("Event tap was disabled (type=\(type.rawValue)); re-enabling")
                if let tap = provider.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

            // Convert flagsChanged to synthetic keyDown/keyUp based on modifier flags
            let effectiveType: CGEventType
            if type == .flagsChanged {
                effectiveType = SystemEventTapProvider.syntheticTypeForFlagsChanged(
                    keyCode: keyCode, flags: event.flags
                )
            } else {
                effectiveType = type
            }

            let consumed = provider.callback?(effectiveType, keyCode) ?? false
            return consumed ? nil : Unmanaged.passUnretained(event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: tapCallback,
            userInfo: selfPtr
        ) else {
            throw TalkKeyError.permissionDenied("Failed to create event tap")
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        callback = nil
    }
}

final class SystemKeyStateProvider: KeyStateProviderProtocol {
    func isKeyDown(_ keyCode: CGKeyCode) -> Bool {
        // イベントタップを通らないハードウェアの状態を見る
        CGEventSource.keyState(.hidSystemState, key: keyCode)
    }
}
