import Foundation

final class FileLogger: LoggerProtocol {
    // テスト実行中は利用者のログ（~/Library/Logs/TalkKey）を汚さないよう一時ディレクトリに書く
    static let shared = FileLogger(directory: defaultDirectory())

    private let fileURL: URL
    private let fileHandle: FileHandle?
    private let queue: DispatchQueue
    private let dateFormatter: ISO8601DateFormatter
    private let synchronous: Bool

    init(directory: URL? = nil, synchronous: Bool = false) {
        self.synchronous = synchronous
        let dir = directory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/TalkKey")
        let url = dir.appendingPathComponent("talkkey.log")
        self.fileURL = url

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.dateFormatter = formatter

        self.queue = DispatchQueue(label: "com.talkkey.logger", qos: .utility)

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        self.fileHandle = try? FileHandle(forWritingTo: url)
        fileHandle?.seekToEndOfFile()
    }

    static func defaultDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if RuntimeEnvironment.isRunningTests(environment: environment) {
            return FileManager.default.temporaryDirectory.appendingPathComponent("TalkKeyTests-logs")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/TalkKey")
    }

    deinit {
        try? fileHandle?.close()
    }

    func log(_ level: LogLevel, _ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "\(timestamp) [\(level.rawValue)] \(message)\n"

        let writeBlock: () -> Void = { [weak self] in
            guard let data = line.data(using: .utf8) else { return }
            self?.fileHandle?.write(data)
        }

        if synchronous {
            writeBlock()
        } else {
            queue.async(execute: writeBlock)
        }
    }
}
