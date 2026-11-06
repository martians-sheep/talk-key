import Foundation
@testable import TalkKey

final class MockHTTPClient: HTTPClientProtocol {
    struct StubResponse {
        var statusCode: Int = 200
        var body: String = ""
        var error: Error?
    }

    private(set) var requests: [URLRequest] = []
    var lastRequest: URLRequest? { requests.last }
    var lastRequestBody: String? {
        lastRequest?.httpBody.flatMap { String(data: $0, encoding: .utf8) }
    }

    // 既定の応答。stubbedResponses が空のときに使う
    var responseBody: String?
    var responseStatusCode = 200
    var responseError: Error?
    var delay: TimeInterval = 0
    // 先頭から順に1回ずつ使う応答
    var stubbedResponses: [StubResponse] = []
    // URL のパスごとの応答（stubbedResponses より優先）
    var responsesByPath: [String: StubResponse] = [:]
    // リクエストごとに応答を決める（最優先）
    var responder: ((URLRequest) -> StubResponse)?

    private let lock = NSLock()

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let stub: StubResponse = lock.withLock {
            requests.append(request)
            if let responder {
                return responder(request)
            }
            if let path = request.url?.path, let byPath = responsesByPath[path] {
                return byPath
            }
            if !stubbedResponses.isEmpty {
                return stubbedResponses.removeFirst()
            }
            return StubResponse(statusCode: responseStatusCode, body: responseBody ?? "", error: responseError)
        }

        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        if let error = stub.error {
            throw error
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(stub.body.utf8), response)
    }
}
