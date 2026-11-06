import Foundation

final class SystemProcessLauncher: ProcessLauncherProtocol {
    func launch(executablePath: String, arguments: [String], outputLogURL: URL?) throws -> LaunchedProcessProtocol {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        if let outputLogURL, let handle = Self.appendingHandle(for: outputLogURL) {
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        try process.run()
        return SystemLaunchedProcess(process: process)
    }

    private static func appendingHandle(for url: URL) -> FileHandle? {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        return handle
    }
}

private final class SystemLaunchedProcess: LaunchedProcessProtocol {
    private let process: Process

    init(process: Process) {
        self.process = process
    }

    var isRunning: Bool { process.isRunning }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }
}
