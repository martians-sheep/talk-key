import Foundation
@testable import TalkKey

final class MockWhisperServerProvider: WhisperServerProviderProtocol {
    var serverURL: URL? = URL(string: "http://127.0.0.1:8178")
    private(set) var readyServerURLCallCount = 0

    func readyServerURL() async -> URL? {
        readyServerURLCallCount += 1
        return serverURL
    }
}
