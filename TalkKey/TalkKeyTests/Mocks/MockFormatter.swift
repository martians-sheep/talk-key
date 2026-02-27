@testable import TalkKey

final class MockFormatter: FormatterProtocol {
    private(set) var formatCalled = false
    private(set) var lastInputText: String?
    private(set) var lastMode: FormattingMode?
    var formatResult: String?

    func format(text: String, mode: FormattingMode) async throws -> String {
        formatCalled = true
        lastInputText = text
        lastMode = mode
        return formatResult ?? text
    }
}
