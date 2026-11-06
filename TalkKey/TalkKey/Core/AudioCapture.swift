import AVFoundation

protocol AudioEngineProviderProtocol: AnyObject {
    func prepare() throws
    func start(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) throws
    func stop()
}

final class AudioCapture: AudioCaptureProtocol {
    var audioBufferHandler: ((AVAudioPCMBuffer) -> Void)?

    private let permissionChecker: PermissionCheckerProtocol
    private let engineProvider: AudioEngineProviderProtocol
    private let logger: LoggerProtocol
    private var isCapturing = false

    init(
        permissionChecker: PermissionCheckerProtocol,
        engineProvider: AudioEngineProviderProtocol = SystemAudioEngineProvider(),
        logger: LoggerProtocol = FileLogger.shared
    ) {
        self.permissionChecker = permissionChecker
        self.engineProvider = engineProvider
        self.logger = logger
    }

    func prepare() {
        guard permissionChecker.checkMicrophonePermission() == .authorized else { return }
        do {
            try engineProvider.prepare()
            logger.debug("Audio engine prepared")
        } catch {
            logger.warning("Failed to prepare audio engine: \(error.localizedDescription)")
        }
    }

    func startCapture() throws {
        guard permissionChecker.checkMicrophonePermission() == .authorized else {
            throw TalkKeyError.permissionDenied("Microphone permission is required")
        }
        guard !isCapturing else { return }

        let latency = FirstBufferLatency(startedAt: Date())
        try engineProvider.start { [weak self] buffer in
            if let elapsedMs = latency.markFirstBuffer() {
                self?.logger.info("First audio buffer after \(elapsedMs)ms")
            }
            self?.audioBufferHandler?(buffer)
        }
        isCapturing = true
    }

    func stopCapture() {
        guard isCapturing else { return }
        engineProvider.stop()
        isCapturing = false
    }
}

/// 押してから最初の音声が届くまでの時間を、1回の録音につき1度だけ測る
private final class FirstBufferLatency {
    private let startedAt: Date
    private let lock = NSLock()
    private var isMarked = false

    init(startedAt: Date) {
        self.startedAt = startedAt
    }

    func markFirstBuffer() -> Int? {
        lock.withLock {
            guard !isMarked else { return nil }
            isMarked = true
            return Int(Date().timeIntervalSince(startedAt) * 1000)
        }
    }
}

/// AVAudioEngine を作り直さずに使い回す。タップは付けたまま、離したら pause でマイクだけ止める
final class SystemAudioEngineProvider: AudioEngineProviderProtocol {
    private let engine = AVAudioEngine()
    private let bufferSize: AVAudioFrameCount = 1024

    private let lock = NSLock()
    private var bufferHandler: ((AVAudioPCMBuffer) -> Void)?
    private var isTapInstalled = false
    private var needsReconfiguration = false
    private var configurationObserver: NSObjectProtocol?

    init() {
        // 入力デバイスが変わるとタップの形式が合わなくなるため、次の開始時に付け直す
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.lock.withLock { self?.needsReconfiguration = true }
        }
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    func prepare() throws {
        try installTapIfNeeded()
        engine.prepare()
    }

    func start(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) throws {
        lock.withLock { self.bufferHandler = bufferHandler }
        do {
            try installTapIfNeeded()
            try engine.start()
        } catch {
            // 形式の不一致などで開始できなければ、一から付け直してもう一度だけ試す
            resetTap()
            try installTapIfNeeded()
            engine.prepare()
            try engine.start()
        }
    }

    func stop() {
        lock.withLock { bufferHandler = nil }
        // stop() だと準備した資源も解放されて次の開始が遅くなるため pause にする。どちらでもマイクは止まる
        engine.pause()
    }

    private func installTapIfNeeded() throws {
        let shouldReconfigure = lock.withLock { () -> Bool in
            let value = needsReconfiguration
            needsReconfiguration = false
            return value
        }
        if shouldReconfigure {
            resetTap()
        }
        guard !isTapInstalled else { return }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw TalkKeyError.transcriptionFailed("No audio input device available")
        }
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let handler = self.lock.withLock { self.bufferHandler }
            handler?(buffer)
        }
        isTapInstalled = true
    }

    private func resetTap() {
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        engine.stop()
        engine.reset()
    }
}
