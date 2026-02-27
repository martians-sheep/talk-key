import XCTest
@testable import TalkKey

// MARK: - TranscriptionResult Tests

final class TranscriptionResultTests: XCTestCase {
    func testInitialization() {
        let now = Date()
        let result = TranscriptionResult(
            rawText: "hello world",
            formattedText: "Hello world.",
            timestamp: now,
            duration: 2.5
        )

        XCTAssertEqual(result.rawText, "hello world")
        XCTAssertEqual(result.formattedText, "Hello world.")
        XCTAssertEqual(result.timestamp, now)
        XCTAssertEqual(result.duration, 2.5)
    }

    func testFormattedTextDefaultsToRawText() {
        let result = TranscriptionResult(
            rawText: "hello world",
            formattedText: nil,
            timestamp: Date(),
            duration: 1.0
        )

        XCTAssertNil(result.formattedText)
        XCTAssertEqual(result.rawText, "hello world")
    }
}

// MARK: - FormattingMode Tests

final class FormattingModeTests: XCTestCase {
    func testAllCases() {
        let allCases = FormattingMode.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.memo))
        XCTAssertTrue(allCases.contains(.email))
        XCTAssertTrue(allCases.contains(.minutes))
        XCTAssertTrue(allCases.contains(.bulletPoints))
    }
}

// MARK: - HistoryEntry Tests

final class HistoryEntryTests: XCTestCase {
    func testInitialization() {
        let now = Date()
        let result = TranscriptionResult(
            rawText: "test",
            formattedText: "Test.",
            timestamp: now,
            duration: 1.0
        )
        let entry = HistoryEntry(
            id: UUID(),
            result: result,
            mode: .memo,
            createdAt: now
        )

        XCTAssertEqual(entry.result.rawText, "test")
        XCTAssertEqual(entry.mode, .memo)
        XCTAssertEqual(entry.createdAt, now)
    }

    func testCodable() throws {
        let now = Date()
        let result = TranscriptionResult(
            rawText: "test",
            formattedText: "Test.",
            timestamp: now,
            duration: 1.0
        )
        let entry = HistoryEntry(
            id: UUID(),
            result: result,
            mode: .email,
            createdAt: now
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(entry)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HistoryEntry.self, from: data)

        XCTAssertEqual(decoded.id, entry.id)
        XCTAssertEqual(decoded.result.rawText, entry.result.rawText)
        XCTAssertEqual(decoded.mode, entry.mode)
    }
}

// MARK: - ServiceStatus Tests

final class ServiceStatusTests: XCTestCase {
    func testAllStates() {
        let idle = ServiceStatus.idle
        let recording = ServiceStatus.recording
        let processing = ServiceStatus.processing
        let inserting = ServiceStatus.inserting
        let error = ServiceStatus.error("test error")

        XCTAssertEqual(idle, .idle)
        XCTAssertEqual(recording, .recording)
        XCTAssertEqual(processing, .processing)
        XCTAssertEqual(inserting, .inserting)

        if case .error(let message) = error {
            XCTAssertEqual(message, "test error")
        } else {
            XCTFail("Expected error state")
        }
    }

    func testEquatable() {
        XCTAssertEqual(ServiceStatus.idle, ServiceStatus.idle)
        XCTAssertEqual(ServiceStatus.recording, ServiceStatus.recording)
        XCTAssertNotEqual(ServiceStatus.idle, ServiceStatus.recording)
        XCTAssertEqual(ServiceStatus.error("a"), ServiceStatus.error("a"))
        XCTAssertNotEqual(ServiceStatus.error("a"), ServiceStatus.error("b"))
    }
}
