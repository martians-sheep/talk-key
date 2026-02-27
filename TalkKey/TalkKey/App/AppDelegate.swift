import AppKit
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var permissionManager: PermissionManager?
    private var hotkeyManager: HotkeyManager?
    private var voiceInputService: VoiceInputService?
    private var historyStore: HistoryStoreProtocol?
    private var keychainHelper: KeychainHelper?
    private var hotkeySettingsStore: HotkeySettingsStore?
    private var settingsWindow: NSWindow?
    private var logViewerWindow: LogViewerWindow?

    private var statusMenuItem: NSMenuItem?
    private var lastResultItem: NSMenuItem?
    private var micPermissionItem: NSMenuItem?
    private var speechPermissionItem: NSMenuItem?
    private var accessibilityPermissionItem: NSMenuItem?
    private var llmToggleItem: NSMenuItem?
    private var modeMenuItems: [FormattingMode: NSMenuItem] = [:]
    private var modelMenuItems: [GeminiModel: NSMenuItem] = [:]
    private var historyMenuItem: NSMenuItem?

    private var llmEnabled: Bool = false
    private var currentMode: FormattingMode = .memo
    private var currentModel: GeminiModel = .defaultModel
    private var apiKey: String = ""

    // Hotkey recording UI state
    private enum HotkeyRecordingStep {
        case none
        case waitingForModifier  // Step 1: "修飾キーを押す（単一キーの場合はEsc）..."
        case waitingForTrigger   // Step 2: "トリガーキーを押す..."
    }
    private var hotkeyRecordingStep: HotkeyRecordingStep = .none
    private var hotkeyEventMonitor: Any?
    private var hotkeyLabel: NSTextField?
    private var hotkeyNoteLabel: NSTextField?
    private var hotkeyChangeButton: NSButton?
    private var hotkeyErrorLabel: NSTextField?
    private var pendingModifierKeyCode: CGKeyCode?

    private var currentStatus: ServiceStatus = .idle {
        didSet { updateStatusDisplay() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let checker = SystemPermissionChecker()
        permissionManager = PermissionManager(checker: checker)

        keychainHelper = KeychainHelper()
        apiKey = (try? keychainHelper?.load(key: "apiKey")) ?? ""
        if let raw = UserDefaults.standard.string(forKey: "selectedModel"),
           let model = GeminiModel(rawValue: raw) {
            currentModel = model
        } else {
            currentModel = .defaultModel
            UserDefaults.standard.set(GeminiModel.defaultModel.rawValue, forKey: "selectedModel")
        }
        setupVoiceInputService(permissionChecker: checker)
        setupMenuBar()
        requestPermissionsOnLaunch()
    }

    private func requestPermissionsOnLaunch() {
        guard let manager = permissionManager else { return }
        NSApp.activate(ignoringOtherApps: true)
        Task {
            let micStatus = manager.microphoneStatus
            FileLogger.shared.info("Microphone status before request: \(micStatus)")
            if micStatus != .authorized {
                let granted = await manager.requestMicrophoneAccess()
                FileLogger.shared.info("Microphone permission granted: \(granted)")
            }
            let speechStatus = manager.speechRecognitionStatus
            FileLogger.shared.info("Speech status before request: \(speechStatus)")
            if speechStatus != .authorized {
                let granted = await manager.requestSpeechRecognitionAccess()
                FileLogger.shared.info("Speech recognition permission granted: \(granted)")
            }
            await MainActor.run {
                updatePermissionDisplay()
                setupHotkeyManager()
            }
        }
    }

    private func setupVoiceInputService(permissionChecker: PermissionCheckerProtocol) {
        let audioCapture = AudioCapture(permissionChecker: permissionChecker)
        let transcriber = Transcriber()
        let notificationSender = SystemNotificationSender()

        let localFormatter = LocalFormatter()
        let llmFormatter = apiKey.isEmpty ? nil : LLMFormatter(apiKey: apiKey, model: currentModel)
        let formatter = FormattingPipeline(
            localFormatter: localFormatter,
            llmFormatter: llmFormatter,
            llmEnabled: llmEnabled,
            notificationSender: notificationSender
        )

        let inserter = Inserter()
        let historyStore = HistoryStore()
        self.historyStore = historyStore

        let service = VoiceInputService(
            audioCapture: audioCapture,
            transcriber: transcriber,
            formatter: formatter,
            inserter: inserter,
            historyStore: historyStore
        )
        service.onStatusChanged = { [weak self] status in
            DispatchQueue.main.async {
                self?.currentStatus = status
            }
        }
        service.notificationSender = notificationSender
        voiceInputService = service
    }

    private func setupHotkeyManager() {
        let store = HotkeySettingsStore()
        hotkeySettingsStore = store
        let savedCombo = store.loadCombo()
        let manager = HotkeyManager(combo: savedCombo)
        manager.onKeyDown = { [weak self] in
            self?.handleHotkeyDown()
        }
        manager.onKeyUp = { [weak self] in
            self?.handleHotkeyUp()
        }
        hotkeyManager = manager
        startHotkeyManagerWithRetry()
    }

    func updateHotkey(combo: HotkeyCombo) throws {
        try hotkeyManager?.updateHotkey(combo: combo)
        hotkeySettingsStore?.save(combo: combo)
    }

    private func startHotkeyManagerWithRetry() {
        guard let manager = hotkeyManager else { return }
        do {
            try manager.start()
            FileLogger.shared.info("Hotkey manager started successfully")
        } catch {
            FileLogger.shared.error("Failed to start hotkey manager: \(error.localizedDescription)")
            let checker = SystemPermissionChecker()
            let _ = checker.requestAccessibilityAccess()
        }
    }

    private func handleHotkeyDown() {
        guard currentStatus == .idle else { return }
        do {
            try voiceInputService?.startRecording()
        } catch {
            FileLogger.shared.error("Failed to start recording: \(error.localizedDescription)")
            currentStatus = .error(error.localizedDescription)
        }
    }

    private func handleHotkeyUp() {
        guard currentStatus == .recording else { return }
        Task {
            do {
                let result = try await voiceInputService?.stopRecording()
                if let text = result?.rawText, !text.isEmpty {
                    await MainActor.run {
                        lastResultItem?.title = "直近: \(String(text.prefix(40)))"
                    }
                    FileLogger.shared.info("Transcription result: \(text)")
                }
            } catch {
                FileLogger.shared.error("Failed to stop recording: \(error.localizedDescription)")
                await MainActor.run {
                    currentStatus = .error(error.localizedDescription)
                }
            }
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()

        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: statusLabel(for: currentStatus), action: nil, keyEquivalent: "")
        menu.addItem(statusMenuItem!)

        lastResultItem = NSMenuItem(title: "直近: (なし)", action: nil, keyEquivalent: "")
        lastResultItem?.isEnabled = false
        menu.addItem(lastResultItem!)

        menu.addItem(NSMenuItem.separator())

        let permissionsHeader = NSMenuItem(title: "権限", action: nil, keyEquivalent: "")
        permissionsHeader.isEnabled = false
        menu.addItem(permissionsHeader)

        micPermissionItem = NSMenuItem(title: "", action: #selector(openMicSettings), keyEquivalent: "")
        micPermissionItem?.target = self
        menu.addItem(micPermissionItem!)

        speechPermissionItem = NSMenuItem(title: "", action: #selector(openSpeechSettings), keyEquivalent: "")
        speechPermissionItem?.target = self
        menu.addItem(speechPermissionItem!)

        accessibilityPermissionItem = NSMenuItem(title: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityPermissionItem?.target = self
        menu.addItem(accessibilityPermissionItem!)

        updatePermissionDisplay()

        menu.addItem(NSMenuItem.separator())

        // LLM formatting toggle
        let llmHeader = NSMenuItem(title: "整形", action: nil, keyEquivalent: "")
        llmHeader.isEnabled = false
        menu.addItem(llmHeader)

        llmToggleItem = NSMenuItem(title: "LLM整形: OFF", action: #selector(toggleLLM), keyEquivalent: "")
        llmToggleItem?.target = self
        menu.addItem(llmToggleItem!)

        // Mode selection submenu
        let modeMenu = NSMenu()
        for mode in FormattingMode.allCases {
            let item = NSMenuItem(title: modeLabel(for: mode), action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            if mode == currentMode {
                item.state = .on
            }
            modeMenu.addItem(item)
            modeMenuItems[mode] = item
        }
        let modeItem = NSMenuItem(title: "モード", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        // Model selection submenu
        let modelMenu = NSMenu()
        for model in GeminiModel.allCases {
            let item = NSMenuItem(title: model.displayName, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model.rawValue
            if model == currentModel {
                item.state = .on
            }
            modelMenu.addItem(item)
            modelMenuItems[model] = item
        }
        let modelItem = NSMenuItem(title: "モデル", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        menu.addItem(NSMenuItem.separator())

        // History submenu
        let historyMenu = NSMenu()
        historyMenuItem = NSMenuItem(title: "履歴", action: nil, keyEquivalent: "")
        historyMenuItem?.submenu = historyMenu
        menu.addItem(historyMenuItem!)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "設定...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let logItem = NSMenuItem(title: "ログを表示...", action: #selector(openLogViewer), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
        menu.delegate = self
    }

    func updateStatus(_ status: ServiceStatus) {
        currentStatus = status
    }

    private func updateStatusDisplay() {
        statusMenuItem?.title = statusLabel(for: currentStatus)
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbolName: String
        switch currentStatus {
        case .idle:
            symbolName = "mic"
        case .recording:
            symbolName = "mic.fill"
        case .processing:
            symbolName = "ellipsis.circle"
        case .inserting:
            symbolName = "doc.on.clipboard"
        case .error:
            symbolName = "exclamationmark.triangle"
        }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "TalkKey")
    }

    private func updatePermissionDisplay() {
        guard let manager = permissionManager else { return }

        let micStatus = manager.microphoneStatus == .authorized
        micPermissionItem?.title = "\(micStatus ? "\u{2713}" : "\u{2717}") マイク"

        let speechStatus = manager.speechRecognitionStatus == .authorized
        speechPermissionItem?.title = "\(speechStatus ? "\u{2713}" : "\u{2717}") 音声認識"

        let axStatus = manager.accessibilityStatus
        accessibilityPermissionItem?.title = "\(axStatus ? "\u{2713}" : "\u{2717}") アクセシビリティ"
    }

    private func statusLabel(for status: ServiceStatus) -> String {
        switch status {
        case .idle: return "状態: 待機中"
        case .recording: return "状態: 録音中..."
        case .processing: return "状態: 処理中..."
        case .inserting: return "状態: 挿入中..."
        case .error(let message): return "状態: エラー - \(message)"
        }
    }

    @objc private func openMicSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openSpeechSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openAccessibilitySettings() {
        permissionManager?.openAccessibilitySettings()
    }

    @objc private func toggleLLM() {
        llmEnabled.toggle()
        llmToggleItem?.title = "LLM整形: \(llmEnabled ? "ON" : "OFF")"
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = FormattingMode(rawValue: rawValue) else { return }
        currentMode = mode
        for (m, item) in modeMenuItems {
            item.state = m == mode ? .on : .off
        }
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let model = GeminiModel(rawValue: rawValue) else { return }
        currentModel = model
        for (m, item) in modelMenuItems {
            item.state = m == model ? .on : .off
        }
        UserDefaults.standard.set(model.rawValue, forKey: "selectedModel")
        rebuildVoiceInputService()
    }

    private func rebuildVoiceInputService() {
        guard currentStatus != .recording else { return }
        let checker = SystemPermissionChecker()
        setupVoiceInputService(permissionChecker: checker)
    }

    private func modeLabel(for mode: FormattingMode) -> String {
        switch mode {
        case .memo: return "メモ"
        case .email: return "メール"
        case .minutes: return "議事録"
        case .bulletPoints: return "箇条書き"
        }
    }

    private func refreshHistoryMenu() {
        guard let historyMenu = historyMenuItem?.submenu else { return }
        historyMenu.removeAllItems()

        let entries = historyStore?.listRecent(limit: 10) ?? []
        if entries.isEmpty {
            let emptyItem = NSMenuItem(title: "(履歴なし)", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            historyMenu.addItem(emptyItem)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short

            for (index, entry) in entries.enumerated() {
                let preview = String(entry.result.rawText.prefix(30))
                let time = formatter.string(from: entry.createdAt)
                let title = "[\(time)] \(preview)"
                let item = NSMenuItem(title: title, action: #selector(copyHistoryEntry(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.representedObject = entry.result.formattedText ?? entry.result.rawText
                historyMenu.addItem(item)
            }
        }

        historyMenu.addItem(NSMenuItem.separator())
        let clearItem = NSMenuItem(title: "履歴を消去", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        historyMenu.addItem(clearItem)
    }

    @objc private func copyHistoryEntry(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func clearHistory() {
        try? historyStore?.clear()
    }

    @objc private func openSettings() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "TalkKey 設定"
        window.center()
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]

        var y: CGFloat = 410

        // API Key section
        let apiKeyLabel = NSTextField(labelWithString: "APIキー (Gemini):")
        apiKeyLabel.frame = NSRect(x: 20, y: y, width: 380, height: 20)
        contentView.addSubview(apiKeyLabel)
        y -= 30

        let apiKeyField = NSSecureTextField(frame: NSRect(x: 20, y: y, width: 280, height: 24))
        apiKeyField.placeholderString = "APIキーを入力..."
        apiKeyField.stringValue = apiKey
        apiKeyField.tag = 100
        contentView.addSubview(apiKeyField)

        let saveButton = NSButton(title: "保存", target: self, action: #selector(saveAPIKey(_:)))
        saveButton.frame = NSRect(x: 310, y: y, width: 50, height: 24)
        saveButton.tag = 100
        contentView.addSubview(saveButton)

        let deleteButton = NSButton(title: "削除", target: self, action: #selector(deleteAPIKey(_:)))
        deleteButton.frame = NSRect(x: 365, y: y, width: 40, height: 24)
        deleteButton.tag = 100
        contentView.addSubview(deleteButton)
        y -= 40

        // Model selection section
        let modelLabel = NSTextField(labelWithString: "モデル:")
        modelLabel.frame = NSRect(x: 20, y: y, width: 380, height: 20)
        contentView.addSubview(modelLabel)
        y -= 30

        let modelPopup = NSPopUpButton(frame: NSRect(x: 20, y: y, width: 280, height: 24))
        modelPopup.removeAllItems()
        for model in GeminiModel.allCases {
            modelPopup.addItem(withTitle: model.displayName)
            modelPopup.lastItem?.representedObject = model.rawValue
        }
        modelPopup.selectItem(withTitle: currentModel.displayName)
        modelPopup.target = self
        modelPopup.action = #selector(settingsSelectModel(_:))
        contentView.addSubview(modelPopup)
        y -= 40

        // LLM Formatting section
        let llmCheck = NSButton(checkboxWithTitle: "LLM整形を有効にする", target: self, action: #selector(settingsToggleLLM(_:)))
        llmCheck.frame = NSRect(x: 20, y: y, width: 380, height: 20)
        llmCheck.state = llmEnabled ? .on : .off
        contentView.addSubview(llmCheck)
        y -= 30

        // Local Formatting section
        let localCheck = NSButton(checkboxWithTitle: "ローカル整形を有効にする", target: nil, action: nil)
        localCheck.frame = NSRect(x: 20, y: y, width: 380, height: 20)
        localCheck.state = .on
        localCheck.isEnabled = false
        contentView.addSubview(localCheck)

        let localNote = NSTextField(labelWithString: "(常に有効)")
        localNote.frame = NSRect(x: 220, y: y, width: 180, height: 20)
        localNote.textColor = .secondaryLabelColor
        localNote.font = .systemFont(ofSize: 11)
        contentView.addSubview(localNote)
        y -= 40

        // Hotkey section
        let currentCombo = hotkeyManager?.currentCombo ?? .default
        let comboName = KeyCodeHelper.comboName(for: currentCombo)
        let hkLabel = NSTextField(labelWithString: "ホットキー: \(comboName)")
        hkLabel.frame = NSRect(x: 20, y: y, width: 250, height: 20)
        contentView.addSubview(hkLabel)
        hotkeyLabel = hkLabel

        let changeBtn = NSButton(title: "変更...", target: self, action: #selector(startHotkeyRecording))
        changeBtn.frame = NSRect(x: 280, y: y - 2, width: 80, height: 24)
        changeBtn.bezelStyle = .rounded
        contentView.addSubview(changeBtn)
        hotkeyChangeButton = changeBtn

        let noteText = currentCombo.isSingleKey
            ? "押して録音、離して入力"
            : "修飾キーを押しながらトリガーキーで録音"
        let hkNote = NSTextField(labelWithString: noteText)
        hkNote.frame = NSRect(x: 20, y: y - 18, width: 380, height: 16)
        hkNote.textColor = .secondaryLabelColor
        hkNote.font = .systemFont(ofSize: 11)
        contentView.addSubview(hkNote)
        hotkeyNoteLabel = hkNote

        let hkError = NSTextField(labelWithString: "")
        hkError.frame = NSRect(x: 20, y: y - 34, width: 380, height: 16)
        hkError.textColor = .systemRed
        hkError.font = .systemFont(ofSize: 11)
        hkError.isHidden = true
        contentView.addSubview(hkError)
        hotkeyErrorLabel = hkError
        y -= 60

        // Permissions section
        let permHeader = NSTextField(labelWithString: "権限:")
        permHeader.frame = NSRect(x: 20, y: y, width: 380, height: 20)
        permHeader.font = .boldSystemFont(ofSize: 13)
        contentView.addSubview(permHeader)
        y -= 25

        let permissions: [(String, Bool, Selector)] = [
            ("マイク", permissionManager?.microphoneStatus == .authorized, #selector(openMicSettings)),
            ("音声認識", permissionManager?.speechRecognitionStatus == .authorized, #selector(openSpeechSettings)),
            ("アクセシビリティ", permissionManager?.accessibilityStatus ?? false, #selector(openAccessibilitySettings)),
        ]

        for (name, granted, action) in permissions {
            let icon = granted ? "\u{2713}" : "\u{2717}"
            let color: NSColor = granted ? .systemGreen : .systemRed
            let label = NSTextField(labelWithString: "\(icon) \(name)")
            label.frame = NSRect(x: 30, y: y, width: 200, height: 20)
            label.textColor = color
            contentView.addSubview(label)

            if !granted {
                let openButton = NSButton(title: "設定を開く", target: self, action: action)
                openButton.frame = NSRect(x: 240, y: y - 2, width: 120, height: 24)
                openButton.bezelStyle = .rounded
                contentView.addSubview(openButton)
            }
            y -= 28
        }

        window.contentView = contentView
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func saveAPIKey(_ sender: NSButton) {
        guard let contentView = settingsWindow?.contentView else { return }
        guard let field = contentView.subviews.compactMap({ $0 as? NSSecureTextField }).first else { return }
        let key = field.stringValue
        guard !key.isEmpty else { return }
        do {
            try keychainHelper?.save(key: "apiKey", value: key)
            apiKey = key
            rebuildVoiceInputService()
        } catch {
            FileLogger.shared.error("Failed to save API key: \(error.localizedDescription)")
        }
    }

    @objc private func deleteAPIKey(_ sender: NSButton) {
        do {
            try keychainHelper?.delete(key: "apiKey")
            apiKey = ""
            if let field = settingsWindow?.contentView?.subviews.compactMap({ $0 as? NSSecureTextField }).first {
                field.stringValue = ""
            }
        } catch {
            FileLogger.shared.error("Failed to delete API key: \(error.localizedDescription)")
        }
    }

    @objc private func settingsSelectModel(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let model = GeminiModel(rawValue: rawValue) else { return }
        currentModel = model
        for (m, item) in modelMenuItems {
            item.state = m == model ? .on : .off
        }
        UserDefaults.standard.set(model.rawValue, forKey: "selectedModel")
        rebuildVoiceInputService()
    }

    @objc private func startHotkeyRecording() {
        guard hotkeyRecordingStep == .none else { return }
        hotkeyRecordingStep = .waitingForModifier
        pendingModifierKeyCode = nil
        hotkeyErrorLabel?.isHidden = true

        // Suspend global hotkey to avoid accidental triggers
        hotkeyManager?.stop()

        hotkeyChangeButton?.title = "修飾キーを押す..."
        hotkeyChangeButton?.isEnabled = false
        hotkeyNoteLabel?.stringValue = "単一キーの場合はEscを押す"

        hotkeyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleHotkeyRecordingEvent(event)
            return nil // consume the event
        }
    }

    private func handleHotkeyRecordingEvent(_ event: NSEvent) {
        let keyCode = CGKeyCode(event.keyCode)

        // Step 1: Accept OS modifier keys (Fn, Shift, etc.) as combo modifier
        if event.type == .flagsChanged {
            // Only process key-down (not key-up) for flagsChanged
            let isDown = Self.isFlagsChangedKeyDown(event)
            guard isDown else { return }

            switch hotkeyRecordingStep {
            case .waitingForModifier:
                // OS modifier key as combo modifier
                pendingModifierKeyCode = keyCode
                hotkeyRecordingStep = .waitingForTrigger
                let modName = KeyCodeHelper.keyName(for: keyCode)
                hotkeyChangeButton?.title = "\(modName) + ..."
                hotkeyNoteLabel?.stringValue = "トリガーキーを押す"
                hotkeyErrorLabel?.isHidden = true
            case .waitingForTrigger:
                // In combo mode, allow OS modifier keys as trigger (e.g. Fn + Command)
                if keyCode == pendingModifierKeyCode {
                    hotkeyErrorLabel?.stringValue = "修飾キーと同じキーは使用できません"
                    hotkeyErrorLabel?.isHidden = false
                } else {
                    let newCombo = HotkeyCombo(modifierKeyCode: pendingModifierKeyCode, triggerKeyCode: keyCode)
                    do {
                        try updateHotkey(combo: newCombo)
                        hotkeyLabel?.stringValue = "ホットキー: \(KeyCodeHelper.comboName(for: newCombo))"
                        hotkeyNoteLabel?.stringValue = "修飾キーを押しながらトリガーキーで録音"
                    } catch {
                        hotkeyErrorLabel?.stringValue = "キーの設定に失敗しました"
                        hotkeyErrorLabel?.isHidden = false
                    }
                    stopHotkeyRecording()
                }
            case .none:
                break
            }
            return
        }

        // Caps Lock is always blocked (toggle behavior)
        if HotkeyManager.blockedSingleKeyCodes.contains(keyCode),
           hotkeyRecordingStep == .waitingForTrigger {
            hotkeyErrorLabel?.stringValue = "Caps Lockはトグル動作のため使用できません"
            hotkeyErrorLabel?.isHidden = false
            return
        }

        hotkeyErrorLabel?.isHidden = true

        switch hotkeyRecordingStep {
        case .waitingForModifier:
            if keyCode == 53 {
                // Esc pressed: enter single-key mode, now wait for trigger
                pendingModifierKeyCode = nil
                hotkeyRecordingStep = .waitingForTrigger
                hotkeyChangeButton?.title = "トリガーキーを押す..."
                hotkeyNoteLabel?.stringValue = "単一キーモード: トリガーキーを押す"
            } else {
                // Normal key as modifier, advance to step 2
                pendingModifierKeyCode = keyCode
                hotkeyRecordingStep = .waitingForTrigger
                let modName = KeyCodeHelper.keyName(for: keyCode)
                hotkeyChangeButton?.title = "\(modName) + ..."
                hotkeyNoteLabel?.stringValue = "トリガーキーを押す"
            }

        case .waitingForTrigger:
            if keyCode == 53 {
                // Esc at step 2: cancel
                stopHotkeyRecording()
                return
            }
            // Check that trigger != modifier
            if let modifier = pendingModifierKeyCode, keyCode == modifier {
                hotkeyErrorLabel?.stringValue = "修飾キーと同じキーは使用できません"
                hotkeyErrorLabel?.isHidden = false
                return
            }
            let newCombo = HotkeyCombo(modifierKeyCode: pendingModifierKeyCode, triggerKeyCode: keyCode)
            do {
                try updateHotkey(combo: newCombo)
                hotkeyLabel?.stringValue = "ホットキー: \(KeyCodeHelper.comboName(for: newCombo))"
                hotkeyNoteLabel?.stringValue = newCombo.isSingleKey
                    ? "押して録音、離して入力"
                    : "修飾キーを押しながらトリガーキーで録音"
            } catch {
                hotkeyErrorLabel?.stringValue = "キーの設定に失敗しました"
                hotkeyErrorLabel?.isHidden = false
            }
            stopHotkeyRecording()

        case .none:
            break
        }
    }

    private static func isFlagsChangedKeyDown(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        let flags = event.modifierFlags
        switch keyCode {
        case 54, 55: return flags.contains(.command)
        case 56, 60: return flags.contains(.shift)
        case 57: return flags.contains(.capsLock)
        case 58, 61: return flags.contains(.option)
        case 59, 62: return flags.contains(.control)
        case 63: return flags.contains(.function)
        default: return false
        }
    }

    private func stopHotkeyRecording() {
        hotkeyRecordingStep = .none
        pendingModifierKeyCode = nil
        hotkeyChangeButton?.title = "変更..."
        hotkeyChangeButton?.isEnabled = true

        // Remove event monitor
        if let monitor = hotkeyEventMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyEventMonitor = nil
        }

        // Resume global hotkey
        startHotkeyManagerWithRetry()
    }

    @objc private func settingsToggleLLM(_ sender: NSButton) {
        llmEnabled = sender.state == .on
        llmToggleItem?.title = "LLM整形: \(llmEnabled ? "ON" : "OFF")"
    }

    @objc private func openLogViewer() {
        if logViewerWindow == nil {
            logViewerWindow = LogViewerWindow(reader: LogFileReader())
        }
        logViewerWindow?.showWindow()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshHistoryMenu()
        updatePermissionDisplay()
        retryHotkeyManagerIfNeeded()
    }
}

extension AppDelegate {
    private func retryHotkeyManagerIfNeeded() {
        guard let manager = hotkeyManager, !manager.isRunning else { return }
        guard permissionManager?.accessibilityStatus == true else { return }
        startHotkeyManagerWithRetry()
    }
}

private final class SystemNotificationSender: NotificationSenderProtocol {
    func send(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
