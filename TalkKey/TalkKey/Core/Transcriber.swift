import AVFoundation
import Speech

protocol SpeechRecognizerProviderProtocol: AnyObject {
    var supportsOnDeviceRecognition: Bool { get }
    func startRecognition(
        locale: Locale,
        resultHandler: @escaping (String, Bool) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) throws
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer)
    func cancelRecognition()
}

final class Transcriber: TranscriberProtocol {
    var partialResultHandler: ((String) -> Void)?

    private let speechProvider: SpeechRecognizerProviderProtocol
    private let autoStopInterval: TimeInterval
    private let logger: LoggerProtocol
    private var latestText: String = ""
    private var finalText: String?
    private var recognitionError: Error?
    private var autoStopTimer: Timer?
    private var isTranscribing = false
    private var startTime: Date?
    private var recognitionGeneration: UInt64 = 0

    init(
        speechProvider: SpeechRecognizerProviderProtocol = SystemSpeechRecognizerProvider(),
        autoStopInterval: TimeInterval = 50.0,
        logger: LoggerProtocol = FileLogger.shared
    ) {
        self.speechProvider = speechProvider
        self.autoStopInterval = autoStopInterval
        self.logger = logger
    }

    var supportsOnDeviceRecognition: Bool {
        speechProvider.supportsOnDeviceRecognition
    }

    func startTranscription() throws {
        guard !isTranscribing else { return }

        logger.debug("Transcription started")
        latestText = ""
        finalText = nil
        recognitionError = nil
        startTime = Date()
        recognitionGeneration += 1
        let currentGeneration = recognitionGeneration

        try speechProvider.startRecognition(
            locale: Locale(identifier: "ja-JP"),
            resultHandler: { [weak self] text, isFinal in
                guard let self = self, self.recognitionGeneration == currentGeneration else { return }
                self.latestText = text
                if isFinal {
                    self.finalText = text
                }
                self.partialResultHandler?(text)
            },
            errorHandler: { [weak self] error in
                guard let self = self, self.recognitionGeneration == currentGeneration else { return }
                self.recognitionError = error
            }
        )

        isTranscribing = true
        scheduleAutoStopTimer()
    }

    func stopTranscription() async throws -> TranscriptionResult {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        speechProvider.cancelRecognition()

        if let error = recognitionError {
            if isNoSpeechDetectedError(error) {
                logger.debug("No speech detected, returning empty result")
            } else {
                logger.error("Transcription error: \(error.localizedDescription)")
                isTranscribing = false
                if let tkError = error as? TalkKeyError {
                    throw tkError
                }
                throw TalkKeyError.transcriptionFailed(error.localizedDescription)
            }
        }

        let text = finalText ?? latestText
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0

        logger.info("Transcription completed: \(String(text.prefix(50)))")
        isTranscribing = false

        return TranscriptionResult(
            rawText: text,
            formattedText: nil,
            timestamp: Date(),
            duration: duration
        )
    }

    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isTranscribing else { return }
        speechProvider.appendAudioBuffer(buffer)
    }

    func triggerAutoStopForTesting() {
        autoStopTimerFired()
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
        speechProvider.cancelRecognition()
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
        resultHandler: @escaping (String, Bool) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) throws {
        // Clean up any previous recognition before starting a new one
        if recognitionTask != nil || recognitionRequest != nil {
            recognitionRequest?.endAudio()
            recognitionTask?.finish()
            recognitionRequest = nil
            recognitionTask = nil
        }

        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw TalkKeyError.transcriptionFailed("Speech recognizer is not available")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

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

    func cancelRecognition() {
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil
    }
}
