import Foundation

protocol LaunchedProcessProtocol: AnyObject {
    var isRunning: Bool { get }
    func terminate()
}

protocol ProcessLauncherProtocol {
    func launch(executablePath: String, arguments: [String], outputLogURL: URL?) throws -> LaunchedProcessProtocol
}
