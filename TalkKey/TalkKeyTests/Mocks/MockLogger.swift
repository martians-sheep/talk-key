@testable import TalkKey

final class MockLogger: LoggerProtocol {
    private(set) var loggedMessages: [(level: LogLevel, message: String)] = []

    func log(_ level: LogLevel, _ message: String) {
        loggedMessages.append((level: level, message: message))
    }

    var lastMessage: String? {
        loggedMessages.last?.message
    }

    var lastLevel: LogLevel? {
        loggedMessages.last?.level
    }
}
