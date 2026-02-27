import XCTest
@testable import TalkKey

final class LogFileReaderTests: XCTestCase {

    // MARK: - LogEntry parsing

    func testParsesValidInfoLogLine() {
        let line = "2026-02-27T05:19:56.507Z [INFO] LLM request: model=gemini-2.5-flash"
        let entry = LogEntry(rawLine: line)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.level, .info)
        XCTAssertEqual(entry?.message, "LLM request: model=gemini-2.5-flash")
        XCTAssertTrue(entry?.timestamp.contains("2026-02-27") ?? false)
    }

    func testParsesValidErrorLogLine() {
        let line = "2026-02-27T05:09:39.152Z [ERROR] LLM error: timeout"
        let entry = LogEntry(rawLine: line)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.level, .error)
        XCTAssertEqual(entry?.message, "LLM error: timeout")
    }

    func testParsesValidWarningLogLine() {
        let line = "2026-02-27T05:09:39.738Z [WARNING] LLM formatting failed"
        let entry = LogEntry(rawLine: line)

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.level, .warning)
    }

    func testReturnsNilForInvalidLine() {
        let entry = LogEntry(rawLine: "garbage text")
        XCTAssertNil(entry)
    }

    func testReturnsNilForEmptyLine() {
        let entry = LogEntry(rawLine: "")
        XCTAssertNil(entry)
    }

    // MARK: - LogFileReader readAll

    func testReadAllReturnsEntriesFromFile() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).log")
        let content = """
        2026-02-27T05:19:56.507Z [INFO] LLM request: model=gemini-2.5-flash
        2026-02-27T05:19:57.123Z [ERROR] LLM error: timeout
        """
        try content.write(to: tmpURL, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmpURL) }

        let reader = LogFileReader(logFileURL: tmpURL)
        let entries = reader.readAll()

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].level, .info)
        XCTAssertEqual(entries[1].level, .error)
    }

    func testReadAllReturnsEmptyForMissingFile() {
        let reader = LogFileReader(logFileURL: URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).log"))
        let entries = reader.readAll()

        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - Filtering

    func testLLMOnlyFilterReturnsOnlyLLMEntries() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).log")
        let content = """
        2026-02-27T05:19:56.507Z [INFO] LLM request: model=gemini-2.5-flash
        2026-02-27T05:19:56.600Z [INFO] App started
        2026-02-27T05:19:57.123Z [INFO] LLM response: chars=42
        """
        try content.write(to: tmpURL, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmpURL) }

        let reader = LogFileReader(logFileURL: tmpURL)
        let entries = reader.readFiltered(filter: .llmOnly)

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.message.contains("LLM ") })
    }

    func testErrorsOnlyFilterReturnsWarningAndError() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).log")
        let content = """
        2026-02-27T05:19:56.507Z [INFO] normal log
        2026-02-27T05:19:56.600Z [WARNING] something wrong
        2026-02-27T05:19:57.123Z [ERROR] critical failure
        2026-02-27T05:19:57.200Z [DEBUG] debug info
        """
        try content.write(to: tmpURL, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmpURL) }

        let reader = LogFileReader(logFileURL: tmpURL)
        let entries = reader.readFiltered(filter: .errorsOnly)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].level, .warning)
        XCTAssertEqual(entries[1].level, .error)
    }
}
