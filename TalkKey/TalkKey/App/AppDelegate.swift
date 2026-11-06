import AppKit
import ServiceManagement
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
    private let launchAtLogin = LaunchAtLoginManager()
    private var launchAtLoginItem: NSMenuItem?
    private var logViewerWindow: LogViewerWindow?

    private var statusMenuItem: NSMenuItem?
    private var lastResultItem: NSMenuItem?
    private var micPermissionItem: NSMenuItem?
    private var speechPermissionItem: NSMenuItem?
    private var accessibilityPermissionItem: NSMenuItem?
    private var llmToggleItem: NSMenuItem?
    private var modeMenuItems: [FormattingMode: NSMenuItem] = [:]
    private var modelMenuItems: [GeminiModel: NSMenuItem] = [:]
    private var providerMenuItems: [LLMProvider: NSMenuItem] = [:]
    private var historyMenuItem: NSMenuItem?

    private var llmEnabled: Bool = false
    private var currentMode: FormattingMode = .memo
    private var currentModel: GeminiModel = .defaultModel
    private var currentProvider: LLMProvider = .defaultProvider
    private var claudeModel: String = ClaudeFormatter.defaultModel
    // キーの値は整形の呼び出しにだけ使い、画面やログには出さない
    private var geminiAPIKey: String = ""
    private var claudeAPIKey: String = ""

    private let recognitionSettingsStore = RecognitionSettingsStore()
    private var recognitionSettings: RecognitionSettings!
    // マイクの準備を使い回すため、サービスを作り直しても同じものを使う
    private let audioEngineProvider = SystemAudioEngineProvider()
    private var whisperServerManager: WhisperServerManager?
    private let isRunningTests = RuntimeEnvironment.isRunningTests()

    private enum DefaultsKeys {
        static let selectedModel = "selectedModel"
        static let llmProvider = "llmProvider"
        static let claudeModel = "claudeModel"
        static let llmEnabled = "llmEnabled"
    }

    private enum SettingsFieldTag {
        static let geminiKey = 100
        static let claudeKey = 101
        static let whisperURL = 102
        static let vocabularyHint = 103
        static let claudeModel = 104
    }

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
        loadLLMSettings()
        recognitionSettings = recognitionSettingsStore.load()
        setupVoiceInputService(permissionChecker: checker)
        setupMenuBar()
        requestPermissionsOnLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 自分で起動した whisper-server だけを止める（共用のサーバーには触れない）
        whisperServerManager?.shutdown()
    }

    private func loadLLMSettings() {
        let defaults = UserDefaults.standard
        // 廃止済みのモデル名が保存されていても既定に移して保存し直す
        currentModel = GeminiModel(storedValue: defaults.string(forKey: DefaultsKeys.selectedModel))
        defaults.set(currentModel.rawValue, forKey: DefaultsKeys.selectedModel)
        currentProvider = LLMProvider(storedValue: defaults.string(forKey: DefaultsKeys.llmProvider))
        if let stored = defaults.string(forKey: DefaultsKeys.claudeModel), !stored.isEmpty {
            claudeModel = stored
        }
        llmEnabled = defaults.bool(forKey: DefaultsKeys.llmEnabled)
        geminiAPIKey = loadAPIKey(for: .gemini)
        claudeAPIKey = loadAPIKey(for: .claude)
    }

    private func loadAPIKey(for provider: LLMProvider) -> String {
        do {
            return try keychainHelper?.load(key: provider.keychainAccount) ?? ""
        } catch {
            FileLogger.shared.error("Failed to load \(provider.displayName) API key: \(error.localizedDescription)")
            return ""
        }
    }

    private func apiKey(for provider: LLMProvider) -> String {
        switch provider {
        case .claude: return claudeAPIKey
        case .gemini: return geminiAPIKey
        }
    }

    /// 起動直後の最初の録音を待たせないよう、マイクと whisper-server の準備を裏で済ませる
    private func warmUpRecognition() {
        guard !isRunningTests else { return }
        voiceInputService?.prepare()
        guard let manager = whisperServerManager else { return }
        Task.detached(priority: .utility) {
            await manager.warmUp()
        }
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
                warmUpRecognition()
            }
        }
    }

    private func setupVoiceInputService(permissionChecker: PermissionCheckerProtocol) {
        let audioCapture = AudioCapture(permissionChecker: permissionChecker, engineProvider: audioEngineProvider)
        let transcriber = makeTranscriber()
        let notificationSender = SystemNotificationSender()

        let localFormatter = LocalFormatter()
        let llmFormatter = makeLLMFormatter()
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

    private func makeTranscriber() -> TranscriberProtocol {
        let settings = recognitionSettings ?? recognitionSettingsStore.load()
        let appleTranscriber = Transcriber(contextualStrings: settings.vocabularyTerms)

        guard settings.engine == .whisperWithAppleFallback else {
            replaceWhisperServerManager(with: nil)
            return appleTranscriber
        }

        let configuration = settings.whisperServerConfiguration
        if whisperServerManager?.configuration != configuration {
            let logURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/TalkKey/whisper-server.log")
            replaceWhisperServerManager(with: WhisperServerManager(configuration: configuration, outputLogURL: logURL))
        }
        guard let manager = whisperServerManager else { return appleTranscriber }

        let whisperTranscriber = WhisperTranscriber(serverProvider: manager, prompt: settings.whisperPrompt)
        return FallbackTranscriber(primary: whisperTranscriber, fallback: appleTranscriber)
    }

    private func replaceWhisperServerManager(with manager: WhisperServerManager?) {
        whisperServerManager?.shutdown()
        whisperServerManager = manager
    }

    private func makeLLMFormatter() -> FormatterProtocol? {
        let key = apiKey(for: currentProvider)
        guard !key.isEmpty else { return nil }
        let vocabulary = recognitionSettings?.vocabularyTerms ?? []
        switch currentProvider {
        case .claude:
            return ClaudeFormatter(apiKey: key, model: claudeModel, vocabularyTerms: vocabulary)
        case .gemini:
            return LLMFormatter(apiKey: key, model: currentModel, vocabularyTerms: vocabulary)
        }
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

    // 画面用の currentStatus は main.async で遅れて反映されるため、押した・離したの判定はサービスの状態で行う
    private func handleHotkeyDown() {
        guard voiceInputService?.status().canStartRecording == true else { return }
        do {
            try voiceInputService?.startRecording()
        } catch {
            FileLogger.shared.error("Failed to start recording: \(error.localizedDescription)")
            currentStatus = .error(error.localizedDescription)
        }
    }

    private func handleHotkeyUp() {
        guard voiceInputService?.status() == .recording else { return }
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

        llmToggleItem = NSMenuItem(title: "LLM整形: \(llmEnabled ? "ON" : "OFF")", action: #selector(toggleLLM), keyEquivalent: "")
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
        let modelItem = NSMenuItem(title: "Gemini モデル", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu

        let providerMenu = NSMenu()
        for provider in LLMProvider.allCases {
            let item = NSMenuItem(title: provider.displayName, action: #selector(selectProvider(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = provider.rawValue
            item.state = provider == currentProvider ? .on : .off
            providerMenu.addItem(item)
            providerMenuItems[provider] = item
        }
        let providerItem = NSMenuItem(title: "整形 LLM", action: nil, keyEquivalent: "")
        providerItem.submenu = providerMenu
        menu.addItem(providerItem)
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

        launchAtLoginItem = NSMenuItem(title: "ログイン時に起動", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem?.target = self
        menu.addItem(launchAtLoginItem!)
        updateLaunchAtLoginItem()

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

    @objc private func toggleLaunchAtLogin() {
        do {
            let status = try launchAtLogin.toggle()
            updateLaunchAtLoginItem()
            if status == .requiresApproval {
                // 承認はシステム設定の「ログイン項目」で利用者が行う
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            SystemNotificationSender().send(title: "TalkKey", message: "ログイン時の起動を切り替えられませんでした: \(error.localizedDescription)")
        }
    }

    private func updateLaunchAtLoginItem() {
        switch launchAtLogin.status {
        case .enabled:
            launchAtLoginItem?.state = .on
            launchAtLoginItem?.title = "ログイン時に起動"
        case .requiresApproval:
            launchAtLoginItem?.state = .mixed
            launchAtLoginItem?.title = "ログイン時に起動（システム設定で許可が必要）"
        case .disabled:
            launchAtLoginItem?.state = .off
            launchAtLoginItem?.title = "ログイン時に起動"
        }
    }

    @objc private func toggleLLM() {
        setLLMEnabled(!llmEnabled)
    }

    // 以前は切り替えても整形パイプラインを作り直しておらず、反映されなかった
    private func setLLMEnabled(_ enabled: Bool) {
        llmEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKeys.llmEnabled)
        llmToggleItem?.title = "LLM整形: \(llmEnabled ? "ON" : "OFF")"
        rebuildVoiceInputService()
    }

    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let provider = LLMProvider(rawValue: rawValue) else { return }
        setProvider(provider)
    }

    private func setProvider(_ provider: LLMProvider) {
        currentProvider = provider
        for (p, item) in providerMenuItems {
            item.state = p == provider ? .on : .off
        }
        UserDefaults.standard.set(provider.rawValue, forKey: DefaultsKeys.llmProvider)
        rebuildVoiceInputService()
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
        UserDefaults.standard.set(model.rawValue, forKey: DefaultsKeys.selectedModel)
        rebuildVoiceInputService()
    }

    private func rebuildVoiceInputService() {
        guard currentStatus != .recording else { return }
        let checker = SystemPermissionChecker()
        setupVoiceInputService(permissionChecker: checker)
        warmUpRecognition()
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
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 720),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "TalkKey 設定"
        window.center()
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]

        var y: CGFloat = 680
        let settings = recognitionSettings ?? recognitionSettingsStore.load()

        // Recognition section
        addSectionHeader("音声認識", to: contentView, y: &y)

        let enginePopup = NSPopUpButton(frame: NSRect(x: 20, y: y, width: 340, height: 24))
        for engine in RecognitionEngine.allCases {
            enginePopup.addItem(withTitle: engine.displayName)
            enginePopup.lastItem?.representedObject = engine.rawValue
        }
        enginePopup.selectItem(withTitle: settings.engine.displayName)
        enginePopup.target = self
        enginePopup.action = #selector(settingsSelectEngine(_:))
        contentView.addSubview(enginePopup)
        y -= 32

        addLabel("whisper-server の URL（応答しなければ 8179 で自動起動）:", to: contentView, y: &y)
        addTextField(
            value: settings.whisperServerURL.absoluteString,
            placeholder: RecognitionSettingsStore.defaultWhisperServerURL.absoluteString,
            tag: SettingsFieldTag.whisperURL,
            saveAction: #selector(saveWhisperURL(_:)),
            to: contentView,
            y: &y
        )

        addLabel("用語のヒント（読点・カンマ・改行で区切る）:", to: contentView, y: &y)
        addTextField(
            value: settings.vocabularyHint,
            placeholder: "例: TalkKey、施行日、新旧対照表",
            tag: SettingsFieldTag.vocabularyHint,
            saveAction: #selector(saveVocabularyHint(_:)),
            to: contentView,
            y: &y
        )
        y -= 8

        // Formatting section
        addSectionHeader("整形", to: contentView, y: &y)

        let llmCheck = NSButton(checkboxWithTitle: "LLM整形を有効にする", target: self, action: #selector(settingsToggleLLM(_:)))
        llmCheck.frame = NSRect(x: 20, y: y, width: 200, height: 20)
        llmCheck.state = llmEnabled ? .on : .off
        contentView.addSubview(llmCheck)

        let providerPopup = NSPopUpButton(frame: NSRect(x: 230, y: y - 2, width: 130, height: 24))
        for provider in LLMProvider.allCases {
            providerPopup.addItem(withTitle: provider.displayName)
            providerPopup.lastItem?.representedObject = provider.rawValue
        }
        providerPopup.selectItem(withTitle: currentProvider.displayName)
        providerPopup.target = self
        providerPopup.action = #selector(settingsSelectProvider(_:))
        contentView.addSubview(providerPopup)
        y -= 32

        addLabel("Claude APIキー:", to: contentView, y: &y)
        addAPIKeyRow(provider: .claude, tag: SettingsFieldTag.claudeKey, to: contentView, y: &y)

        addLabel("Claude モデル:", to: contentView, y: &y)
        addTextField(
            value: claudeModel,
            placeholder: ClaudeFormatter.defaultModel,
            tag: SettingsFieldTag.claudeModel,
            saveAction: #selector(saveClaudeModel(_:)),
            to: contentView,
            y: &y
        )

        addLabel("Gemini APIキー:", to: contentView, y: &y)
        addAPIKeyRow(provider: .gemini, tag: SettingsFieldTag.geminiKey, to: contentView, y: &y)

        addLabel("Gemini モデル:", to: contentView, y: &y)
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
        y -= 32

        let localCheck = NSButton(checkboxWithTitle: "ローカル整形を有効にする", target: nil, action: nil)
        localCheck.frame = NSRect(x: 20, y: y, width: 200, height: 20)
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

    // MARK: - Settings window helpers

    private func addSectionHeader(_ title: String, to view: NSView, y: inout CGFloat) {
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 20, y: y, width: 420, height: 20)
        label.font = .boldSystemFont(ofSize: 13)
        view.addSubview(label)
        y -= 28
    }

    private func addLabel(_ title: String, to view: NSView, y: inout CGFloat) {
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 20, y: y, width: 420, height: 18)
        label.font = .systemFont(ofSize: 12)
        view.addSubview(label)
        y -= 24
    }

    private func addTextField(
        value: String,
        placeholder: String,
        tag: Int,
        saveAction: Selector,
        to view: NSView,
        y: inout CGFloat
    ) {
        let field = NSTextField(frame: NSRect(x: 20, y: y, width: 340, height: 24))
        field.stringValue = value
        field.placeholderString = placeholder
        field.tag = tag
        view.addSubview(field)

        let saveButton = NSButton(title: "保存", target: self, action: saveAction)
        saveButton.frame = NSRect(x: 365, y: y, width: 60, height: 24)
        view.addSubview(saveButton)
        y -= 34
    }

    private func addAPIKeyRow(provider: LLMProvider, tag: Int, to view: NSView, y: inout CGFloat) {
        let field = NSSecureTextField(frame: NSRect(x: 20, y: y, width: 280, height: 24))
        // 登録済みのキーは読み出して表示しない
        field.placeholderString = apiKey(for: provider).isEmpty ? "APIキーを入力..." : "登録済み（変更するときだけ入力）"
        field.tag = tag
        view.addSubview(field)

        let saveButton = NSButton(title: "保存", target: self, action: #selector(saveAPIKey(_:)))
        saveButton.frame = NSRect(x: 305, y: y, width: 55, height: 24)
        saveButton.identifier = NSUserInterfaceItemIdentifier(provider.rawValue)
        view.addSubview(saveButton)

        let deleteButton = NSButton(title: "削除", target: self, action: #selector(deleteAPIKey(_:)))
        deleteButton.frame = NSRect(x: 365, y: y, width: 60, height: 24)
        deleteButton.identifier = NSUserInterfaceItemIdentifier(provider.rawValue)
        view.addSubview(deleteButton)
        y -= 34
    }

    private func settingsField(tag: Int) -> NSTextField? {
        settingsWindow?.contentView?.subviews
            .compactMap { $0 as? NSTextField }
            .first { $0.tag == tag && $0.isEditable }
    }

    private func provider(of sender: NSButton) -> LLMProvider? {
        sender.identifier.flatMap { LLMProvider(rawValue: $0.rawValue) }
    }

    private func keyFieldTag(for provider: LLMProvider) -> Int {
        provider == .claude ? SettingsFieldTag.claudeKey : SettingsFieldTag.geminiKey
    }

    @objc private func saveAPIKey(_ sender: NSButton) {
        guard let provider = provider(of: sender),
              let field = settingsField(tag: keyFieldTag(for: provider)) else { return }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try keychainHelper?.save(key: provider.keychainAccount, value: key)
            switch provider {
            case .claude: claudeAPIKey = key
            case .gemini: geminiAPIKey = key
            }
            field.stringValue = ""
            field.placeholderString = "登録済み（変更するときだけ入力）"
            FileLogger.shared.info("\(provider.displayName) API key saved")
            rebuildVoiceInputService()
        } catch {
            FileLogger.shared.error("Failed to save \(provider.displayName) API key: \(error.localizedDescription)")
        }
    }

    @objc private func deleteAPIKey(_ sender: NSButton) {
        guard let provider = provider(of: sender) else { return }
        do {
            try keychainHelper?.delete(key: provider.keychainAccount)
            switch provider {
            case .claude: claudeAPIKey = ""
            case .gemini: geminiAPIKey = ""
            }
            if let field = settingsField(tag: keyFieldTag(for: provider)) {
                field.stringValue = ""
                field.placeholderString = "APIキーを入力..."
            }
            FileLogger.shared.info("\(provider.displayName) API key deleted")
            rebuildVoiceInputService()
        } catch {
            FileLogger.shared.error("Failed to delete \(provider.displayName) API key: \(error.localizedDescription)")
        }
    }

    @objc private func settingsSelectModel(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let model = GeminiModel(rawValue: rawValue) else { return }
        currentModel = model
        for (m, item) in modelMenuItems {
            item.state = m == model ? .on : .off
        }
        UserDefaults.standard.set(model.rawValue, forKey: DefaultsKeys.selectedModel)
        rebuildVoiceInputService()
    }

    @objc private func settingsSelectProvider(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let provider = LLMProvider(rawValue: rawValue) else { return }
        setProvider(provider)
    }

    @objc private func saveClaudeModel(_ sender: NSButton) {
        guard let field = settingsField(tag: SettingsFieldTag.claudeModel) else { return }
        let model = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        claudeModel = model.isEmpty ? ClaudeFormatter.defaultModel : model
        field.stringValue = claudeModel
        UserDefaults.standard.set(claudeModel, forKey: DefaultsKeys.claudeModel)
        rebuildVoiceInputService()
    }

    @objc private func settingsSelectEngine(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let engine = RecognitionEngine(rawValue: rawValue) else { return }
        updateRecognitionSettings { $0.engine = engine }
    }

    @objc private func saveWhisperURL(_ sender: NSButton) {
        guard let field = settingsField(tag: SettingsFieldTag.whisperURL) else { return }
        guard let url = RecognitionSettingsStore.parseServerURL(field.stringValue) else {
            field.stringValue = recognitionSettings.whisperServerURL.absoluteString
            NSSound.beep()
            return
        }
        updateRecognitionSettings { $0.whisperServerURL = url }
    }

    @objc private func saveVocabularyHint(_ sender: NSButton) {
        guard let field = settingsField(tag: SettingsFieldTag.vocabularyHint) else { return }
        updateRecognitionSettings { $0.vocabularyHint = field.stringValue }
    }

    private func updateRecognitionSettings(_ change: (inout RecognitionSettings) -> Void) {
        var settings = recognitionSettings ?? recognitionSettingsStore.load()
        change(&settings)
        recognitionSettings = settings
        recognitionSettingsStore.save(settings)
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
        setLLMEnabled(sender.state == .on)
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
