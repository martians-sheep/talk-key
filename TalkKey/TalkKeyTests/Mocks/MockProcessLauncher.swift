import Foundation
@testable import TalkKey

final class MockLaunchedProcess: LaunchedProcessProtocol {
    var isRunning = true
    private(set) var terminateCalled = false

    func terminate() {
        terminateCalled = true
        isRunning = false
    }
}

final class MockProcessLauncher: ProcessLauncherProtocol {
    struct Launch {
        let executablePath: String
        let arguments: [String]
    }

    private let lock = NSLock()
    private var _launches: [Launch] = []
    var launches: [Launch] { lock.withLock { _launches } }
    var launchError: Error?
    var processToReturn = MockLaunchedProcess()

    func launch(executablePath: String, arguments: [String], outputLogURL: URL?) throws -> LaunchedProcessProtocol {
        if let launchError { throw launchError }
        lock.withLock { _launches.append(Launch(executablePath: executablePath, arguments: arguments)) }
        return processToReturn
    }
}
