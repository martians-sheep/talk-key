@testable import TalkKey

final class MockInserter: InserterProtocol {
    private(set) var insertCalled = false
    private(set) var insertedTexts: [String] = []
    var insertError: Error?

    func insert(text: String) async throws {
        insertCalled = true
        insertedTexts.append(text)
        if let error = insertError {
            throw error
        }
    }
}
