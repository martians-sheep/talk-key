@testable import TalkKey

final class MockHistoryStore: HistoryStoreProtocol {
    private(set) var savedEntries: [HistoryEntry] = []
    private(set) var clearCalled = false

    func save(entry: HistoryEntry) throws {
        savedEntries.append(entry)
    }

    func listRecent(limit: Int) -> [HistoryEntry] {
        Array(savedEntries.suffix(limit))
    }

    func clear() throws {
        savedEntries.removeAll()
        clearCalled = true
    }
}
