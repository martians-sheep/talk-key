import Foundation

protocol HistoryStoreProtocol {
    func save(entry: HistoryEntry) throws
    func listRecent(limit: Int) -> [HistoryEntry]
    func clear() throws
}
