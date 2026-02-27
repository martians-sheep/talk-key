import XCTest
@testable import TalkKey

final class FileLoggerTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - LogLevel tests

    func testLogLevelRawValues() {
        XCTAssertEqual(LogLevel.debug.rawValue, "DEBUG")
        XCTAssertEqual(LogLevel.info.rawValue, "INFO")
        XCTAssertEqual(LogLevel.warning.rawValue, "WARNING")
        XCTAssertEqual(LogLevel.error.rawValue, "ERROR")
    }

    func testLogLevelComparison() {
        XCTAssertTrue(LogLevel.debug < LogLevel.info)
        XCTAssertTrue(LogLevel.info < LogLevel.warning)
        XCTAssertTrue(LogLevel.warning < LogLevel.error)
        XCTAssertFalse(LogLevel.error < LogLevel.debug)
    }

    // MARK: - FileLogger file creation

    func testCreatesDirectoryIfMissing() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path))
        _ = FileLogger(directory: tempDirectory, synchronous: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.path))
    }

    func testCreatesLogFileIfMissing() {
        let logger = FileLogger(directory: tempDirectory, synchronous: true)
        let logPath = tempDirectory.appendingPathComponent("talkkey.log").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: logPath))
        _ = logger // keep reference alive
    }

    // MARK: - FileLogger write behavior

    func testLogWritesMessageToFile() {
        let logger = FileLogger(directory: tempDirectory, synchronous: true)
        logger.log(.info, "test message")

        let content = readLogFile()
        XCTAssertTrue(content.contains("[INFO]"))
        XCTAssertTrue(content.contains("test message"))
    }

    func testLogAppendsMultipleLines() {
        let logger = FileLogger(directory: tempDirectory, synchronous: true)
        logger.log(.info, "first")
        logger.log(.error, "second")

        let content = readLogFile()
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("[INFO]"))
        XCTAssertTrue(lines[1].contains("[ERROR]"))
    }

    func testLogFormatsWithTimestamp() {
        let logger = FileLogger(directory: tempDirectory, synchronous: true)
        logger.log(.debug, "timestamped")

        let content = readLogFile()
        // ISO8601 timestamp should contain 'T' and timezone info
        XCTAssertTrue(content.contains("T"))
        XCTAssertTrue(content.contains("[DEBUG]"))
    }

    func testLogFormatsCorrectLevel() {
        let logger = FileLogger(directory: tempDirectory, synchronous: true)
        logger.log(.warning, "warn msg")

        let content = readLogFile()
        XCTAssertTrue(content.contains("[WARNING] warn msg"))
    }

    // MARK: - Convenience methods

    func testConvenienceMethodsCallLogWithCorrectLevel() {
        let mock = MockLogger()
        mock.debug("d")
        mock.info("i")
        mock.warning("w")
        mock.error("e")

        XCTAssertEqual(mock.loggedMessages.count, 4)
        XCTAssertEqual(mock.loggedMessages[0].level, .debug)
        XCTAssertEqual(mock.loggedMessages[1].level, .info)
        XCTAssertEqual(mock.loggedMessages[2].level, .warning)
        XCTAssertEqual(mock.loggedMessages[3].level, .error)
    }

    // MARK: - Helper

    private func readLogFile() -> String {
        let logPath = tempDirectory.appendingPathComponent("talkkey.log")
        return (try? String(contentsOf: logPath, encoding: .utf8)) ?? ""
    }
}
