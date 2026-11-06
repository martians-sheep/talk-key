import Foundation

/// whisper-server を確保する。共用のサーバーが応答すればそれを使い、なければ自分で起動して準備できるまで待つ。
/// 自分で起動したものだけを終了時に止める
final class WhisperServerManager: WhisperServerProviderProtocol {
    static let defaultReadinessTimeout: TimeInterval = 60
    static let defaultPollInterval: TimeInterval = 0.2

    private enum Constants {
        static let healthCheckTimeout: TimeInterval = 0.5
        // 起動に失敗した直後は押すたびに起動し直さない
        static let relaunchBackoff: TimeInterval = 30
    }

    let configuration: WhisperServerConfiguration
    private let httpClient: HTTPClientProtocol
    private let processLauncher: ProcessLauncherProtocol
    private let fileExists: (String) -> Bool
    private let readinessTimeout: TimeInterval
    private let pollInterval: TimeInterval
    private let outputLogURL: URL?
    private let logger: LoggerProtocol

    private let lock = NSLock()
    private var ownProcess: LaunchedProcessProtocol?
    private var warmUpTask: Task<URL?, Never>?
    private var lastLaunchFailure: Date?

    init(
        configuration: WhisperServerConfiguration,
        httpClient: HTTPClientProtocol = URLSessionHTTPClient(),
        processLauncher: ProcessLauncherProtocol = SystemProcessLauncher(),
        fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        readinessTimeout: TimeInterval = WhisperServerManager.defaultReadinessTimeout,
        pollInterval: TimeInterval = WhisperServerManager.defaultPollInterval,
        outputLogURL: URL? = nil,
        logger: LoggerProtocol = FileLogger.shared
    ) {
        self.configuration = configuration
        self.httpClient = httpClient
        self.processLauncher = processLauncher
        self.fileExists = fileExists
        self.readinessTimeout = readinessTimeout
        self.pollInterval = pollInterval
        self.outputLogURL = outputLogURL
        self.logger = logger
    }

    func readyServerURL() async -> URL? {
        if let url = await firstHealthyServer() {
            return url
        }
        // 録音を待たせないよう、ここでは起動を待たずに裏で準備を始める（この回は Apple 認識を使う）
        startWarmUpIfNeeded()
        return nil
    }

    /// 使えるサーバーを確保する。必要なら起動して準備できるまで待つ。同時に呼ばれても起動は1回
    @discardableResult
    func warmUp() async -> URL? {
        await startWarmUpIfNeeded().value
    }

    func shutdown() {
        let process: LaunchedProcessProtocol? = lock.withLock {
            let process = ownProcess
            ownProcess = nil
            warmUpTask?.cancel()
            return process
        }
        guard let process else { return }
        logger.info("Stopping own whisper-server on port \(configuration.ownPort)")
        process.terminate()
    }

    // MARK: - Private

    @discardableResult
    private func startWarmUpIfNeeded() -> Task<URL?, Never> {
        lock.withLock {
            if let warmUpTask { return warmUpTask }
            let task = Task<URL?, Never> { [weak self] in
                guard let self else { return nil }
                let url = await self.resolveServer()
                self.lock.withLock { self.warmUpTask = nil }
                return url
            }
            warmUpTask = task
            return task
        }
    }

    private func firstHealthyServer() async -> URL? {
        if await isHealthy(configuration.primaryURL) {
            return configuration.primaryURL
        }
        if await isHealthy(configuration.ownURL) {
            return configuration.ownURL
        }
        return nil
    }

    private func resolveServer() async -> URL? {
        if let url = await firstHealthyServer() {
            logger.info("whisper-server ready: \(url.absoluteString)")
            return url
        }

        guard fileExists(configuration.binaryPath) else {
            logger.warning("whisper unavailable: binary not found at \(configuration.binaryPath)")
            return nil
        }
        guard fileExists(configuration.modelPath) else {
            logger.warning("whisper unavailable: model not found at \(configuration.modelPath)")
            return nil
        }

        let process: LaunchedProcessProtocol
        if let running = lock.withLock({ ownProcess }), running.isRunning {
            process = running
        } else {
            if let failedAt = lock.withLock({ lastLaunchFailure }),
               Date().timeIntervalSince(failedAt) < Constants.relaunchBackoff {
                return nil
            }
            guard let launched = launchOwnServer() else { return nil }
            process = launched
        }

        return await waitUntilReady(process)
    }

    private func launchOwnServer() -> LaunchedProcessProtocol? {
        var arguments = [
            "-m", configuration.modelPath,
            "-l", "ja",
            "-t", String(configuration.threads),
            "--host", "127.0.0.1",
            "--port", String(configuration.ownPort),
        ]
        if fileExists(configuration.vadModelPath) {
            arguments += ["--vad", "--vad-model", configuration.vadModelPath]
        } else {
            logger.warning("VAD model not found at \(configuration.vadModelPath); starting whisper-server without VAD")
        }

        do {
            let process = try processLauncher.launch(
                executablePath: configuration.binaryPath,
                arguments: arguments,
                outputLogURL: outputLogURL
            )
            lock.withLock { ownProcess = process }
            logger.info("Launched own whisper-server on port \(configuration.ownPort)")
            return process
        } catch {
            logger.error("Failed to launch whisper-server: \(error.localizedDescription)")
            lock.withLock { lastLaunchFailure = Date() }
            return nil
        }
    }

    private func waitUntilReady(_ process: LaunchedProcessProtocol) async -> URL? {
        let startedAt = Date()
        while Date().timeIntervalSince(startedAt) < readinessTimeout {
            if Task.isCancelled { return nil }
            guard process.isRunning else {
                logger.error("whisper-server exited before becoming ready")
                lock.withLock {
                    if ownProcess === process { ownProcess = nil }
                    lastLaunchFailure = Date()
                }
                return nil
            }
            if await isHealthy(configuration.ownURL) {
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                logger.info("Own whisper-server ready in \(elapsedMs)ms")
                return configuration.ownURL
            }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        logger.warning("whisper-server did not become ready within \(readinessTimeout)s")
        return nil
    }

    private func isHealthy(_ baseURL: URL) async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = Constants.healthCheckTimeout
        guard let (_, response) = try? await httpClient.send(request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}
