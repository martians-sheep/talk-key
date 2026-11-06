import Foundation

/// operation が timeout 秒以内に終わらなければ TalkKeyError.formattingFailed("LLM timeout") を投げる
func withTimeout<T: Sendable>(
    _ timeout: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw TalkKeyError.formattingFailed("LLM timeout")
        }
        guard let result = try await group.next() else {
            throw TalkKeyError.formattingFailed("LLM timeout")
        }
        group.cancelAll()
        return result
    }
}
