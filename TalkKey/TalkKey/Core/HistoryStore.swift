import Foundation

final class HistoryStore: HistoryStoreProtocol {
    private let fileURL: URL
    private let maxCount: Int
    private var entries: [HistoryEntry] = []

    init(directory: URL? = nil, maxCount: Int = 10) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("TalkKey")
        self.fileURL = dir.appendingPathComponent("history.json")
        self.maxCount = maxCount

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        loadFromDisk()
    }

    func save(entry: HistoryEntry) throws {
        entries.append(entry)
        if entries.count > maxCount {
            entries = Array(entries.suffix(maxCount))
        }
        try saveToDisk()
    }

    func listRecent(limit: Int) -> [HistoryEntry] {
        let sorted = entries.sorted { $0.createdAt > $1.createdAt }
        return Array(sorted.prefix(limit))
    }

    func clear() throws {
        entries.removeAll()
        try saveToDisk()
    }

    // MARK: - Private

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func saveToDisk() throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}
