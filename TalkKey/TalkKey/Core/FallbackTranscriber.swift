import AVFoundation

/// 主（whisper）と予備（Apple 認識）に同じ音声を並行で渡し、主が使えないときだけ予備の結果を使う
final class FallbackTranscriber: TranscriberProtocol {
    var partialResultHandler: ((String) -> Void)? {
        didSet { fallback.partialResultHandler = partialResultHandler }
    }

    private let primary: TranscriberProtocol
    private let fallback: TranscriberProtocol
    private let logger: LoggerProtocol

    private let lock = NSLock()
    private var isPrimaryActive = false
    private var isFallbackActive = false
    private var pendingFallbackStop: Task<TranscriptionResult, Error>?

    init(primary: TranscriberProtocol, fallback: TranscriberProtocol, logger: LoggerProtocol = FileLogger.shared) {
        self.primary = primary
        self.fallback = fallback
        self.logger = logger
    }

    func startTranscription() throws {
        let isPreviousFallbackStopping = lock.withLock { pendingFallbackStop != nil }

        var primaryError: Error?
        do {
            try primary.startTranscription()
        } catch {
            primaryError = error
            logger.warning("Primary transcriber failed to start: \(error.localizedDescription)")
        }

        var fallbackError: Error?
        if isPreviousFallbackStopping {
            // 前回の予備の停止がまだ終わっていないので、今回は予備を使わない
            logger.debug("Fallback transcriber still stopping; skipping it for this recording")
        } else {
            do {
                try fallback.startTranscription()
            } catch {
                fallbackError = error
                logger.warning("Fallback transcriber failed to start: \(error.localizedDescription)")
            }
        }

        let primaryActive = primaryError == nil
        let fallbackActive = !isPreviousFallbackStopping && fallbackError == nil
        guard primaryActive || fallbackActive else {
            throw primaryError ?? fallbackError ?? TalkKeyError.transcriptionFailed("No transcriber available")
        }
        lock.withLock {
            isPrimaryActive = primaryActive
            isFallbackActive = fallbackActive
        }
    }

    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        let (primaryActive, fallbackActive) = lock.withLock { (isPrimaryActive, isFallbackActive) }
        if primaryActive { primary.feedAudioBuffer(buffer) }
        if fallbackActive { fallback.feedAudioBuffer(buffer) }
    }

    func stopTranscription() async throws -> TranscriptionResult {
        let (primaryActive, fallbackActive) = lock.withLock { () -> (Bool, Bool) in
            let state = (isPrimaryActive, isFallbackActive)
            isPrimaryActive = false
            isFallbackActive = false
            return state
        }

        // 予備は最終結果を最大1秒待つため、主の処理と並行して止めておく
        let fallbackStop: Task<TranscriptionResult, Error>? = fallbackActive ? startFallbackStop() : nil

        guard primaryActive else {
            guard let fallbackStop else { throw TalkKeyError.notRecording }
            return try await fallbackStop.value
        }

        do {
            let result = try await primary.stopTranscription()
            if !result.rawText.isEmpty {
                return result
            }
            // 主が空のときだけ、予備が何か聞き取っていればそちらを使う
            guard let fallbackStop, let fallbackResult = try? await fallbackStop.value,
                  !fallbackResult.rawText.isEmpty else {
                return result
            }
            logger.info("Primary transcriber returned empty; using fallback result")
            return fallbackResult
        } catch {
            guard let fallbackStop else { throw error }
            logger.warning("Primary transcriber failed, using fallback: \(error.localizedDescription)")
            return try await fallbackStop.value
        }
    }

    /// テスト用: 裏で走っている予備の停止が終わるまで待つ
    func waitForPendingFallbackStopForTesting() async {
        let task = lock.withLock { pendingFallbackStop }
        _ = try? await task?.value
    }

    private func startFallbackStop() -> Task<TranscriptionResult, Error> {
        lock.withLock {
            let task = Task { [fallback, weak self] () throws -> TranscriptionResult in
                defer { self?.lock.withLock { self?.pendingFallbackStop = nil } }
                return try await fallback.stopTranscription()
            }
            pendingFallbackStop = task
            return task
        }
    }
}
