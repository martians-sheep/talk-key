@testable import TalkKey
import XCTest

final class HistoryStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var sut: HistoryStore!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        sut = HistoryStore(directory: tempDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        sut = nil
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeEntry(
        rawText: String = "テスト",
        formattedText: String? = nil,
        mode: FormattingMode = .memo,
        createdAt: Date = Date()
    ) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            result: TranscriptionResult(
                rawText: rawText,
                formattedText: formattedText,
                timestamp: createdAt,
                duration: 1.0
            ),
            mode: mode,
            createdAt: createdAt
        )
    }

    // MARK: - 3-1 Tests

    func test_save_canSaveAndRetrieveEntry() throws {
        let entry = makeEntry(rawText: "保存テスト")

        try sut.save(entry: entry)
        let recent = sut.listRecent(limit: 10)

        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.result.rawText, "保存テスト")
    }

    func test_listRecent_returnsNewestFirstLimitedToN() throws {
        let now = Date()
        let entry1 = makeEntry(rawText: "古い", createdAt: now.addingTimeInterval(-20))
        let entry2 = makeEntry(rawText: "中間", createdAt: now.addingTimeInterval(-10))
        let entry3 = makeEntry(rawText: "新しい", createdAt: now)

        try sut.save(entry: entry1)
        try sut.save(entry: entry2)
        try sut.save(entry: entry3)

        let recent = sut.listRecent(limit: 2)

        XCTAssertEqual(recent.count, 2)
        XCTAssertEqual(recent[0].result.rawText, "新しい")
        XCTAssertEqual(recent[1].result.rawText, "中間")
    }

    func test_save_prunesOldEntriesWhenExceedingMaxCount() throws {
        let store = HistoryStore(directory: tempDirectory, maxCount: 3)

        for i in 0..<5 {
            let entry = makeEntry(
                rawText: "エントリ\(i)",
                createdAt: Date().addingTimeInterval(Double(i))
            )
            try store.save(entry: entry)
        }

        let recent = store.listRecent(limit: 10)

        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent[0].result.rawText, "エントリ4")
        XCTAssertEqual(recent[1].result.rawText, "エントリ3")
        XCTAssertEqual(recent[2].result.rawText, "エントリ2")
    }

    func test_clear_removesAllEntries() throws {
        try sut.save(entry: makeEntry(rawText: "削除対象"))
        try sut.save(entry: makeEntry(rawText: "削除対象2"))

        try sut.clear()
        let recent = sut.listRecent(limit: 10)

        XCTAssertTrue(recent.isEmpty)
    }

    func test_persistence_entriesSurviveNewInstance() throws {
        let entry = makeEntry(rawText: "永続化テスト")
        try sut.save(entry: entry)

        let newStore = HistoryStore(directory: tempDirectory)
        let recent = newStore.listRecent(limit: 10)

        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.result.rawText, "永続化テスト")
    }

    func test_codable_entryEncodesAndDecodesCorrectly() throws {
        let entry = makeEntry(
            rawText: "エンコードテスト",
            formattedText: "整形済み",
            mode: .email
        )
        try sut.save(entry: entry)

        let newStore = HistoryStore(directory: tempDirectory)
        let recent = newStore.listRecent(limit: 10)

        XCTAssertEqual(recent.first?.result.rawText, "エンコードテスト")
        XCTAssertEqual(recent.first?.result.formattedText, "整形済み")
        XCTAssertEqual(recent.first?.mode, .email)
    }

    func test_corruptedFile_doesNotCrash() throws {
        let filePath = tempDirectory.appendingPathComponent("history.json")
        try "{ broken json data".data(using: .utf8)!.write(to: filePath)

        let store = HistoryStore(directory: tempDirectory)
        let recent = store.listRecent(limit: 10)

        XCTAssertTrue(recent.isEmpty)
    }
}
