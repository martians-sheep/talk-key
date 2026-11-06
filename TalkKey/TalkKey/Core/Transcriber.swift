import AVFoundation
import Speech

protocol SpeechRecognizerProviderProtocol: AnyObject {
    var supportsOnDeviceRecognition: Bool { get }
    func startRecognition(
        locale: Locale,
        contextualStrings: [String],
        resultHandler: @escaping (String, Bool) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) throws
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer)
    /// 音声の入力を終える。認識タスクは残し、最終結果を受け取れるようにする
    func finishAudio()
    func cancelRecognition()
}

final class Transcriber: TranscriberProtocol {
    static let defaultFinalResultTimeout: TimeInterval = 1.0

    var partialResultHandler: ((String) -> Void)?

    private let speechProvider: SpeechRecognizerProviderProtocol
    private let autoStopInterval: TimeInterval
    private let finalResultTimeout: TimeInterval
    private let contextualStrings: [String]
    private let logger: LoggerProtocol

    // 認識結果のコールバックは別スレッドから届くため、以下の状態は lock で守る
    private let lock = NSLock()
    private var latestText: String = ""
    private var finalText: String?
    private var recognitionError: Error?
    private var finalWaiter: CheckedContinuation<Void, Never>?
    private var recognitionGeneration: UInt64 = 0

    private var autoStopTimer: Timer?
    private var isTranscribing = false
    private var startTime: Date?

    init(
        speechProvider: SpeechRecognizerProviderProtocol = SystemSpeechRecognizerProvider(),
        autoStopInterval: TimeInterval = 50.0,
        finalResultTimeout: TimeInterval = Transcriber.defaultFinalResultTimeout,
        contextualStrings: [String] = [],
        logger: LoggerProtocol = FileLogger.shared
    ) {
        self.speechProvider = speechProvider
        self.autoStopInterval = autoStopInterval
        self.finalResultTimeout = finalResultTimeout
        self.contextualStrings = contextualStrings
        self.logger = logger
    }

    var supportsOnDeviceRecognition: Bool {
        speechProvider.supportsOnDeviceRecognition
    }

    func startTranscription() throws {
        guard !isTranscribing else { return }

        logger.debug("Transcription started")
        let currentGeneration: UInt64 = lock.withLock {
            latestText = ""
            finalText = nil
            recognitionError = nil
            finalWaiter = nil
            recognitionGeneration += 1
            return recognitionGeneration
        }
        startTime = Date()

        try speechProvider.startRecognition(
            locale: Locale(identifier: "ja-JP"),
            contextualStrings: contextualStrings,
            resultHandler: { [weak self] text, isFinal in
                self?.handleResult(text: text, isFinal: isFinal, generation: currentGeneration)
            },
            errorHandler: { [weak self] error in
                self?.handleError(error, generation: currentGeneration)
            }
        )

        isTranscribing = true
        scheduleAutoStopTimer()
    }

    func stopTranscription() async throws -> TranscriptionResult {
        autoStopTimer?.invalidate()
        autoStopTimer = nil

        // endAudio の直後に打ち切ると語尾が欠けたり空になったりするため、最終結果を少し待つ
        speechProvider.finishAudio()
        let receivedFinal = await waitForFinalResult()
        speechProvider.cancelRecognition()
        isTranscribing = false

        let (text, error) = lock.withLock { (finalText ?? latestText, recognitionError) }

        if let error, !text.isEmpty {
            // 途中でエラーになっても、聞き取れたところまでは使う
            logger.warning("Transcription error after partial result, using partial: \(error.localizedDescription)")
        } else if let error {
            if isNoSpeechDetectedError(error) {
                logger.debug("No speech detected, returning empty result")
            } else {
                logger.error("Transcription error: \(error.localizedDescription)")
                if let tkError = error as? TalkKeyError {
                    throw tkError
                }
                throw TalkKeyError.transcriptionFailed(error.localizedDescription)
            }
        }

        if !receivedFinal {
            logger.debug("Final result did not arrive within \(finalResultTimeout)s; using latest partial")
        }

        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        logger.info("Transcription completed: \(String(text.prefix(50)))")

        return TranscriptionResult(
            rawText: text,
            formattedText: nil,
            timestamp: Date(),
            duration: duration,
            engine: .apple
        )
    }

    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isTranscribing else { return }
        speechProvider.appendAudioBuffer(buffer)
    }

    func triggerAutoStopForTesting() {
        autoStopTimerFired()
    }

    // MARK: - Result handling

    private func handleResult(text: String, isFinal: Bool, generation: UInt64) {
        let waiter: CheckedContinuation<Void, Never>? = lock.withLock {
            guard recognitionGeneration == generation else { return nil }
            latestText = text
            guard isFinal else { return nil }
            finalText = text
            return takeFinalWaiter()
        }
        partialResultHandlerIfCurrent(text: text, generation: generation)
        waiter?.resume()
    }

    private func partialResultHandlerIfCurrent(text: String, generation: UInt64) {
        let isCurrent = lock.withLock { recognitionGeneration == generation }
        if isCurrent {
            partialResultHandler?(text)
        }
    }

    private func handleError(_ error: Error, generation: UInt64) {
        let waiter: CheckedContinuation<Void, Never>? = lock.withLock {
            guard recognitionGeneration == generation else { return nil }
            recognitionError = error
            // エラーの後に最終結果は来ないので、待っている停止処理を先に進める
            return takeFinalWaiter()
        }
        waiter?.resume()
    }

    /// lock を取った状態で呼ぶ
    private func takeFinalWaiter() -> CheckedContinuation<Void, Never>? {
        let waiter = finalWaiter
        finalWaiter = nil
        return waiter
    }

    /// 最終結果が届いたら true。エラーやタイムアウトなら false
    private func waitForFinalResult() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyDone: Bool = lock.withLock {
                if finalText != nil || recognitionError != nil { return true }
                finalWaiter = continuation
                return false
            }
            if alreadyDone {
                continuation.resume()
                return
            }
            let timeout = finalResultTimeout
            Task { [weak self] in
                // タイムアウト待ちが取り消されても、待っている側は必ず再開させる
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                let waiter = self?.lock.withLock { self?.takeFinalWaiter() } ?? nil
                waiter?.resume()
            }
        }
        return lock.withLock { finalText != nil }
    }

    private func isNoSpeechDetectedError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1101
    }

    private func scheduleAutoStopTimer() {
        autoStopTimer = Timer.scheduledTimer(
            withTimeInterval: autoStopInterval,
            repeats: false
        ) { [weak self] _ in
            self?.autoStopTimerFired()
        }
    }

    private func autoStopTimerFired() {
        logger.warning("Auto-stop timer fired after \(autoStopInterval)s")
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        // 認識の上限に達したので入力だけ止める。最終結果は停止時に受け取る
        speechProvider.finishAudio()
    }
}

final class SystemSpeechRecognizerProvider: SpeechRecognizerProviderProtocol {
    private let recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    var supportsOnDeviceRecognition: Bool {
        recognizer?.supportsOnDeviceRecognition ?? false
    }

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    }

    func startRecognition(
        locale: Locale,
        contextualStrings: [String],
        resultHandler: @escaping (String, Bool) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) throws {
        // Clean up any previous recognition before starting a new one
        if recognitionTask != nil || recognitionRequest != nil {
            cancelRecognition()
        }

        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw TalkKeyError.transcriptionFailed("Speech recognizer is not available")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // オンデバイス固定は精度が落ちるため、サーバー認識も許す
        request.requiresOnDeviceRecognition = false
        request.addsPunctuation = true
        request.contextualStrings = contextualStrings

        recognitionRequest = request
        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            if let error = error {
                errorHandler(error)
                return
            }
            guard let result = result else { return }
            let text = result.bestTranscription.formattedString
            resultHandler(text, result.isFinal)
        }
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func finishAudio() {
        recognitionRequest?.endAudio()
    }

    func cancelRecognition() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }
}
