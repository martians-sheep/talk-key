import XCTest
import AVFoundation
@testable import TalkKey

final class WhisperTranscriberTests: XCTestCase {
    private var server: MockWhisperServerProvider!
    private var client: MockHTTPClient!
    private var logger: MockLogger!

    override func setUp() {
        super.setUp()
        server = MockWhisperServerProvider()
        client = MockHTTPClient()
        logger = MockLogger()
    }

    private func makeTranscriber(prompt: String = "") -> WhisperTranscriber {
        WhisperTranscriber(serverProvider: server, httpClient: client, prompt: prompt, logger: logger)
    }

    private func record(_ transcriber: WhisperTranscriber, seconds: TimeInterval) throws {
        try transcriber.startTranscription()
        for buffer in TestAudioBuffers.chunks(duration: seconds) {
            transcriber.feedAudioBuffer(buffer)
        }
    }

    private func requestBody() -> String {
        String(decoding: client.lastRequest?.httpBody ?? Data(), as: UTF8.self)
    }

    func test_stop_sendsRecordedAudioAsWavAndReturnsText() async throws {
        client.responseBody = #"{"text":" 今日は晴れです。\n"}"#
        let transcriber = makeTranscriber()
        try record(transcriber, seconds: 1)

        let result = try await transcriber.stopTranscription()

        XCTAssertEqual(result.rawText, "今日は晴れです。")
        XCTAssertEqual(result.engine, .whisper)
        XCTAssertEqual(client.lastRequest?.url?.absoluteString, "http://127.0.0.1:8178/inference")
        let body = client.lastRequest?.httpBody ?? Data()
        // 1 秒 × 16kHz × 2 byte に WAV ヘッダーを足した程度の大きさ
        XCTAssertGreaterThan(body.count, 31_000)
        XCTAssertLessThan(body.count, 34_000)
        XCTAssertTrue(requestBody().contains("audio_ctx"))
    }

    func test_stop_passesPromptToServer() async throws {
        client.responseBody = #"{"text":"施行日"}"#
        let transcriber = makeTranscriber(prompt: "施行日、新旧対照表")
        try record(transcriber, seconds: 0.5)

        _ = try await transcriber.stopTranscription()

        XCTAssertTrue(requestBody().contains("施行日、新旧対照表"))
    }

    func test_stop_withLongAudio_omitsAudioContext() async throws {
        client.responseBody = #"{"text":"長い文"}"#
        let transcriber = makeTranscriber()
        try record(transcriber, seconds: 15)

        _ = try await transcriber.stopTranscription()

        XCTAssertFalse(requestBody().contains("audio_ctx"))
    }

    func test_stop_whenServerUnavailable_throwsWithoutRequest() async throws {
        server.serverURL = nil
        let transcriber = makeTranscriber()
        try record(transcriber, seconds: 0.5)

        do {
            _ = try await transcriber.stopTranscription()
            XCTFail("Expected error")
        } catch {
            guard case TalkKeyError.transcriptionFailed = error else {
                return XCTFail("Expected transcriptionFailed, got \(error)")
            }
        }
        XCTAssertTrue(client.requests.isEmpty)
    }

    func test_stop_withHTTPError_throwsAndLogsStatus() async throws {
        client.responseStatusCode = 500
        client.responseBody = "failed to read audio"
        let transcriber = makeTranscriber()
        try record(transcriber, seconds: 0.5)

        do {
            _ = try await transcriber.stopTranscription()
            XCTFail("Expected error")
        } catch {
            guard case TalkKeyError.transcriptionFailed = error else {
                return XCTFail("Expected transcriptionFailed, got \(error)")
            }
        }
        let logs = logger.loggedMessages.map(\.message).joined(separator: "\n")
        XCTAssertTrue(logs.contains("500"))
        XCTAssertTrue(logs.contains("failed to read audio"))
    }

    func test_stop_withHallucinatedPhraseOnly_returnsEmpty() async throws {
        client.responseBody = #"{"text":"ご視聴ありがとうございました。"}"#
        let transcriber = makeTranscriber()
        try record(transcriber, seconds: 0.5)

        let result = try await transcriber.stopTranscription()

        XCTAssertEqual(result.rawText, "")
    }

    func test_stop_withoutAudio_returnsEmptyWithoutRequest() async throws {
        let transcriber = makeTranscriber()
        try transcriber.startTranscription()

        let result = try await transcriber.stopTranscription()

        XCTAssertEqual(result.rawText, "")
        XCTAssertTrue(client.requests.isEmpty)
    }

    func test_feed_beforeStart_isIgnored() async throws {
        client.responseBody = #"{"text":"x"}"#
        let transcriber = makeTranscriber()
        transcriber.feedAudioBuffer(TestAudioBuffers.sine(duration: 1))
        try transcriber.startTranscription()

        let result = try await transcriber.stopTranscription()

        XCTAssertEqual(result.rawText, "")
    }

    func test_stop_joinsSegmentLinesIntoOneText() async throws {
        client.responseBody = #"{"text":"一文目です。\n二文目です。\n"}"#
        let transcriber = makeTranscriber()
        try record(transcriber, seconds: 0.5)

        let result = try await transcriber.stopTranscription()

        XCTAssertEqual(result.rawText, "一文目です。二文目です。")
    }

    // MARK: - Hallucination filter

    func test_isHallucination_detectsKnownPhrasesOnly() {
        XCTAssertTrue(WhisperTranscriber.isHallucination("ご視聴ありがとうございました"))
        XCTAssertTrue(WhisperTranscriber.isHallucination("ご清聴ありがとうございました。"))
        XCTAssertTrue(WhisperTranscriber.isHallucination(" チャンネル登録よろしくお願いします！"))
        XCTAssertTrue(WhisperTranscriber.isHallucination("字幕"))
        XCTAssertTrue(WhisperTranscriber.isHallucination("ご視聴ありがとうございました ご視聴ありがとうございました"))
        XCTAssertFalse(WhisperTranscriber.isHallucination("本日はご清聴ありがとうございました、と最後に言う"))
        XCTAssertFalse(WhisperTranscriber.isHallucination("字幕を付けてください"))
        XCTAssertFalse(WhisperTranscriber.isHallucination(""))
    }
}
