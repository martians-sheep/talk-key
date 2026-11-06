import XCTest
@testable import TalkKey

final class WhisperServerManagerTests: XCTestCase {
    private var client: MockHTTPClient!
    private var launcher: MockProcessLauncher!
    private var logger: MockLogger!
    private var existingFiles: Set<String>!
    private let lock = NSLock()
    private var ownHealthChecks = 0

    private let configuration = WhisperServerConfiguration(
        primaryURL: URL(string: "http://127.0.0.1:8178")!,
        ownPort: 8179,
        binaryPath: "/opt/whisper/whisper-server",
        modelPath: "/models/ggml-large-v3-turbo-q5_0.bin",
        vadModelPath: "/models/ggml-silero-v6.2.0.bin",
        threads: 8
    )

    override func setUp() {
        super.setUp()
        client = MockHTTPClient()
        launcher = MockProcessLauncher()
        logger = MockLogger()
        existingFiles = [configuration.binaryPath, configuration.modelPath, configuration.vadModelPath]
    }

    private func makeManager(readinessTimeout: TimeInterval = 2) -> WhisperServerManager {
        let files = existingFiles!
        return WhisperServerManager(
            configuration: configuration,
            httpClient: client,
            processLauncher: launcher,
            fileExists: { files.contains($0) },
            readinessTimeout: readinessTimeout,
            pollInterval: 0.01,
            logger: logger
        )
    }

    /// primary(8178) と own(8179) の /health の応答を決める。ownReadyAfter 回目以降で own が準備完了になる
    private func stubHealth(primaryUp: Bool, ownReadyAfter: Int? = nil) {
        client.responder = { [unowned self] request in
            let port = request.url?.port
            if port == 8178 {
                return primaryUp ? .init(statusCode: 200, body: #"{"status":"ok"}"#) : .init(error: URLError(.cannotConnectToHost))
            }
            let count = self.lock.withLock { () -> Int in
                self.ownHealthChecks += 1
                return self.ownHealthChecks
            }
            guard let readyAfter = ownReadyAfter else { return .init(error: URLError(.cannotConnectToHost)) }
            if count >= readyAfter { return .init(statusCode: 200, body: #"{"status":"ok"}"#) }
            return .init(statusCode: 503, body: #"{"status":"loading model"}"#)
        }
    }

    // MARK: - Shared server

    func test_readyServerURL_whenPrimaryHealthy_returnsPrimaryWithoutLaunching() async {
        stubHealth(primaryUp: true)
        let manager = makeManager()

        let url = await manager.readyServerURL()

        XCTAssertEqual(url, configuration.primaryURL)
        XCTAssertTrue(launcher.launches.isEmpty)
        XCTAssertEqual(client.requests.first?.url?.path, "/health")
    }

    // MARK: - Own server

    func test_warmUp_whenPrimaryDown_launchesOwnServerAndWaitsUntilReady() async {
        stubHealth(primaryUp: false, ownReadyAfter: 4)
        let manager = makeManager()

        let url = await manager.warmUp()

        XCTAssertEqual(url, URL(string: "http://127.0.0.1:8179"))
        XCTAssertEqual(launcher.launches.count, 1)
        XCTAssertEqual(launcher.launches.first?.executablePath, configuration.binaryPath)
        XCTAssertEqual(launcher.launches.first?.arguments, [
            "-m", configuration.modelPath,
            "-l", "ja",
            "-t", "8",
            "--host", "127.0.0.1",
            "--port", "8179",
            "--vad", "--vad-model", configuration.vadModelPath,
        ])
    }

    func test_warmUp_whenVADModelMissing_launchesWithoutVAD() async {
        existingFiles.remove(configuration.vadModelPath)
        stubHealth(primaryUp: false, ownReadyAfter: 2)
        let manager = makeManager()

        _ = await manager.warmUp()

        XCTAssertEqual(launcher.launches.first.map { $0.arguments.contains("--vad") }, false)
    }

    func test_warmUp_whenBinaryMissing_returnsNilWithoutLaunching() async {
        existingFiles.remove(configuration.binaryPath)
        stubHealth(primaryUp: false)
        let manager = makeManager()

        let url = await manager.warmUp()

        XCTAssertNil(url)
        XCTAssertTrue(launcher.launches.isEmpty)
    }

    func test_warmUp_whenModelMissing_returnsNilWithoutLaunching() async {
        existingFiles.remove(configuration.modelPath)
        stubHealth(primaryUp: false)
        let manager = makeManager()

        let url = await manager.warmUp()

        XCTAssertNil(url)
        XCTAssertTrue(launcher.launches.isEmpty)
    }

    func test_warmUp_whenOwnPortAlreadyServing_usesItWithoutLaunching() async {
        stubHealth(primaryUp: false, ownReadyAfter: 1)
        let manager = makeManager()

        let url = await manager.warmUp()

        XCTAssertEqual(url, URL(string: "http://127.0.0.1:8179"))
        XCTAssertTrue(launcher.launches.isEmpty)
    }

    func test_warmUp_whenProcessExitsBeforeReady_returnsNil() async {
        stubHealth(primaryUp: false)
        launcher.processToReturn.isRunning = false
        let manager = makeManager()

        let url = await manager.warmUp()

        XCTAssertNil(url)
        XCTAssertFalse(logger.loggedMessages.filter { $0.level == .error }.isEmpty)
    }

    func test_warmUp_whenNeverReady_givesUpAfterTimeout() async {
        stubHealth(primaryUp: false)
        let manager = makeManager(readinessTimeout: 0.1)

        let url = await manager.warmUp()

        XCTAssertNil(url)
    }

    func test_warmUp_calledConcurrently_launchesOnce() async {
        stubHealth(primaryUp: false, ownReadyAfter: 6)
        let manager = makeManager()

        async let first = manager.warmUp()
        async let second = manager.warmUp()
        let urls = await [first, second]

        XCTAssertEqual(urls.compactMap { $0 }.count, 2)
        XCTAssertEqual(launcher.launches.count, 1)
    }

    // MARK: - Not blocking the first recording

    func test_readyServerURL_whenNothingReady_returnsNilAndStartsLaunchInBackground() async {
        stubHealth(primaryUp: false, ownReadyAfter: 3)
        let manager = makeManager()

        let url = await manager.readyServerURL()
        let warmed = await manager.warmUp()

        XCTAssertNil(url)
        XCTAssertNotNil(warmed)
        XCTAssertEqual(launcher.launches.count, 1)
    }

    func test_readyServerURL_afterOwnServerReady_returnsOwn() async {
        stubHealth(primaryUp: false, ownReadyAfter: 2)
        let manager = makeManager()
        _ = await manager.warmUp()

        let url = await manager.readyServerURL()

        XCTAssertEqual(url, URL(string: "http://127.0.0.1:8179"))
    }

    // MARK: - Shutdown

    func test_shutdown_terminatesOnlyOwnLaunchedProcess() async {
        stubHealth(primaryUp: false, ownReadyAfter: 2)
        let manager = makeManager()
        _ = await manager.warmUp()

        manager.shutdown()

        XCTAssertTrue(launcher.processToReturn.terminateCalled)
    }

    func test_shutdown_whenUsingSharedServer_doesNothing() async {
        stubHealth(primaryUp: true)
        let manager = makeManager()
        _ = await manager.warmUp()

        manager.shutdown()

        XCTAssertFalse(launcher.processToReturn.terminateCalled)
    }
}
