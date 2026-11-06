import Foundation

protocol NotificationSenderProtocol: AnyObject {
    func send(title: String, message: String)
}

final class VoiceInputService {
    private let audioCapture: AudioCaptureProtocol
    private let transcriber: TranscriberProtocol
    private let formatter: FormatterProtocol
    private let inserter: InserterProtocol
    private let historyStore: HistoryStoreProtocol
    private let logger: LoggerProtocol

    private(set) var currentStatus: ServiceStatus = .idle
    var onStatusChanged: ((ServiceStatus) -> Void)?
    var onAutoStopped: ((TranscriptionResult) -> Void)?
    var notificationSender: NotificationSenderProtocol?

    init(
        audioCapture: AudioCaptureProtocol,
        transcriber: TranscriberProtocol,
        formatter: FormatterProtocol,
        inserter: InserterProtocol,
        historyStore: HistoryStoreProtocol,
        logger: LoggerProtocol = FileLogger.shared
    ) {
        self.audioCapture = audioCapture
        self.transcriber = transcriber
        self.formatter = formatter
        self.inserter = inserter
        self.historyStore = historyStore
        self.logger = logger
    }

    func prepare() {
        audioCapture.prepare()
    }

    func startRecording() throws {
        guard currentStatus.canStartRecording else {
            throw TalkKeyError.alreadyRecording
        }

        logger.info("Recording started")

        audioCapture.audioBufferHandler = { [weak self] buffer in
            self?.transcriber.feedAudioBuffer(buffer)
        }

        try audioCapture.startCapture()
        do {
            try transcriber.startTranscription()
        } catch {
            // 認識を始められないままマイクだけ動き続けないよう止める
            audioCapture.stopCapture()
            throw error
        }
        updateStatus(.recording)
    }

    func stopRecording() async throws -> TranscriptionResult {
        guard currentStatus == .recording else {
            throw TalkKeyError.notRecording
        }
        let releasedAt = Date()
        audioCapture.stopCapture()
        updateStatus(.processing)

        do {
            let result = try await transcriber.stopTranscription()
            let recognizedAt = Date()
            var formattedText: String?
            var formattedAt = recognizedAt

            defer {
                logMetrics(
                    result: result,
                    releasedAt: releasedAt,
                    recognizedAt: recognizedAt,
                    formattedAt: formattedAt
                )
            }

            if !result.rawText.isEmpty {
                logger.info("Transcription: \(result.rawText)")
                let formatted = try await formatter.format(text: result.rawText, mode: .memo)
                formattedAt = Date()
                formattedText = formatted
                let textToInsert = formatted.isEmpty ? result.rawText : formatted

                updateStatus(.inserting)
                do {
                    try await inserter.insert(text: textToInsert)
                } catch {
                    logger.warning("Insertion failed: \(error.localizedDescription)")
                    notificationSender?.send(
                        title: "TalkKey",
                        message: "テキスト挿入に失敗しました。手動で貼り付けてください。"
                    )
                }
            }

            let entry = HistoryEntry(
                id: UUID(),
                result: TranscriptionResult(
                    rawText: result.rawText,
                    formattedText: formattedText,
                    timestamp: result.timestamp,
                    duration: result.duration
                ),
                mode: .memo,
                createdAt: Date()
            )
            try? historyStore.save(entry: entry)

            updateStatus(.idle)
            return result
        } catch {
            let failureEntry = HistoryEntry(
                id: UUID(),
                result: TranscriptionResult(
                    rawText: "",
                    formattedText: nil,
                    timestamp: Date(),
                    duration: 0
                ),
                mode: .memo,
                createdAt: Date()
            )
            try? historyStore.save(entry: failureEntry)

            logger.error("Pipeline error: \(error.localizedDescription)")
            updateStatus(.error(error.localizedDescription))
            throw error
        }
    }

    func status() -> ServiceStatus {
        currentStatus
    }

    /// 離してから挿入までの内訳を1行で残す（速さの調査用）
    private func logMetrics(result: TranscriptionResult, releasedAt: Date, recognizedAt: Date, formattedAt: Date) {
        let now = Date()
        let recognizeMs = Int(recognizedAt.timeIntervalSince(releasedAt) * 1000)
        let formatMs = Int(formattedAt.timeIntervalSince(recognizedAt) * 1000)
        let totalMs = Int(now.timeIntervalSince(releasedAt) * 1000)
        let engine = result.engine?.rawValue ?? "unknown"
        let textInfo = result.rawText.isEmpty ? "empty" : "chars=\(result.rawText.count)"
        logger.info("Metrics: engine=\(engine) recognize=\(recognizeMs)ms format=\(formatMs)ms total=\(totalMs)ms \(textInfo)")
    }

    private func updateStatus(_ newStatus: ServiceStatus) {
        currentStatus = newStatus
        onStatusChanged?(newStatus)
    }
}
