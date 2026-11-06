import AVFoundation

/// whisper.cpp の whisper-server で文字起こしする。録音中は音声をためておき、離したら一度に送る
final class WhisperTranscriber: TranscriberProtocol {
    static let defaultRequestTimeout: TimeInterval = 20

    private enum Constants {
        static let errorBodyLogLimit = 300
        // 無音や雑音に対して whisper がよく出す決まり文句。これだけの結果は空として扱う
        static let hallucinationPhrases = [
            "ご視聴ありがとうございました",
            "ご清聴ありがとうございました",
            "チャンネル登録よろしくお願いします",
            "チャンネル登録お願いします",
            "チャンネル登録",
            "字幕",
        ]
    }

    var partialResultHandler: ((String) -> Void)?

    private let serverProvider: WhisperServerProviderProtocol
    private let httpClient: HTTPClientProtocol
    private let prompt: String
    private let requestTimeout: TimeInterval
    private let logger: LoggerProtocol

    // feedAudioBuffer はオーディオスレッドから呼ばれるため lock で守る
    private let lock = NSLock()
    private let resampler = PCM16Resampler()
    private var isTranscribing = false
    private var startTime: Date?

    init(
        serverProvider: WhisperServerProviderProtocol,
        httpClient: HTTPClientProtocol = URLSessionHTTPClient(),
        prompt: String = "",
        requestTimeout: TimeInterval = WhisperTranscriber.defaultRequestTimeout,
        logger: LoggerProtocol = FileLogger.shared
    ) {
        self.serverProvider = serverProvider
        self.httpClient = httpClient
        self.prompt = prompt
        self.requestTimeout = requestTimeout
        self.logger = logger
    }

    func startTranscription() throws {
        lock.withLock {
            resampler.reset()
            isTranscribing = true
            startTime = Date()
        }
    }

    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard isTranscribing else { return }
            resampler.append(buffer)
        }
    }

    func stopTranscription() async throws -> TranscriptionResult {
        let (samples, startTime) = lock.withLock { () -> ([Int16], Date?) in
            isTranscribing = false
            return (resampler.finish(), self.startTime)
        }
        let recordedDuration = startTime.map { Date().timeIntervalSince($0) } ?? 0

        guard !samples.isEmpty else {
            logger.debug("Whisper: no audio captured")
            return makeResult(text: "", duration: recordedDuration)
        }

        guard let serverURL = await serverProvider.readyServerURL() else {
            throw TalkKeyError.transcriptionFailed("whisper-server is not available")
        }

        let audioDuration = Double(samples.count) / PCM16Resampler.targetSampleRate
        let wav = WAVEncoder.encode(samples: samples, sampleRate: Int(PCM16Resampler.targetSampleRate))
        let request = WhisperRequestBuilder.makeRequest(
            serverURL: serverURL,
            wavData: wav,
            audioDuration: audioDuration,
            prompt: prompt,
            timeout: requestTimeout
        )

        let (data, response) = try await sendRequest(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = HTTPErrorBody.prefix(of: data, limit: Constants.errorBodyLogLimit, redacting: "")
            logger.error("Whisper HTTP \(status): \(body)")
            throw TalkKeyError.transcriptionFailed("whisper-server HTTP \(status)")
        }

        let text = try parseText(data)
        if Self.isHallucination(text) {
            logger.info("Whisper: discarded hallucinated phrase: \(text)")
            return makeResult(text: "", duration: recordedDuration)
        }
        logger.info("Transcription completed (whisper, audio=\(String(format: "%.1f", audioDuration))s): \(String(text.prefix(50)))")
        return makeResult(text: text, duration: recordedDuration)
    }

    static func isHallucination(_ text: String) -> Bool {
        var remainder = text.unicodeScalars
            .filter { !CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines).union(.symbols).contains($0) }
            .map(String.init)
            .joined()
        guard !remainder.isEmpty else { return false }
        for phrase in Constants.hallucinationPhrases {
            remainder = remainder.replacingOccurrences(of: phrase, with: "")
        }
        return remainder.isEmpty
    }

    private func sendRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await httpClient.send(request)
        } catch {
            logger.error("Whisper request failed: \(error.localizedDescription)")
            throw TalkKeyError.transcriptionFailed("whisper-server request failed: \(error.localizedDescription)")
        }
    }

    private func parseText(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw TalkKeyError.transcriptionFailed("whisper-server returned an invalid response")
        }
        // whisper は区間ごとに改行を入れて返すが、日本語の文は改行なしでつなげて入力する
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined()
    }

    private func makeResult(text: String, duration: TimeInterval) -> TranscriptionResult {
        TranscriptionResult(rawText: text, formattedText: nil, timestamp: Date(), duration: duration, engine: .whisper)
    }
}
