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

    func startRecording() throws {
        guard currentStatus == .idle else {
            throw TalkKeyError.alreadyRecording
        }

        logger.info("Recording started")

        audioCapture.audioBufferHandler = { [weak self] buffer in
            self?.transcriber.feedAudioBuffer(buffer)
        }

        try audioCapture.startCapture()
        try transcriber.startTranscription()
        updateStatus(.recording)
    }

    func stopRecording() async throws -> TranscriptionResult {
        guard currentStatus == .recording else {
            throw TalkKeyError.notRecording
        }
        audioCapture.stopCapture()
        updateStatus(.processing)

        do {
            let result = try await transcriber.stopTranscription()
            var formattedText: String?

            if !result.rawText.isEmpty {
                logger.info("Transcription: \(result.rawText)")
                let formatted = try await formatter.format(text: result.rawText, mode: .memo)
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

    private func updateStatus(_ newStatus: ServiceStatus) {
        currentStatus = newStatus
        onStatusChanged?(newStatus)
    }
}
