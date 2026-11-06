import XCTest
@testable import TalkKey

final class WhisperRequestBuilderTests: XCTestCase {
    private let serverURL = URL(string: "http://127.0.0.1:8178")!

    private func makeRequest(duration: TimeInterval = 3, prompt: String = "") -> URLRequest {
        WhisperRequestBuilder.makeRequest(
            serverURL: serverURL,
            wavData: Data([0x52, 0x49, 0x46, 0x46]),
            audioDuration: duration,
            prompt: prompt,
            timeout: 20,
            boundary: "BOUNDARY"
        )
    }

    private func body(_ request: URLRequest) -> String {
        String(decoding: request.httpBody ?? Data(), as: UTF8.self)
    }

    private func field(_ name: String, _ value: String) -> String {
        "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
    }

    func test_makeRequest_postsMultipartToInference() {
        let request = makeRequest()

        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:8178/inference")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=BOUNDARY")
        XCTAssertEqual(request.timeoutInterval, 20)
    }

    func test_makeRequest_includesWavFileAndFixedFields() {
        let text = body(makeRequest())

        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\nRIFF\r\n"))
        XCTAssertTrue(text.contains(field("language", "ja")))
        XCTAssertTrue(text.contains(field("response_format", "json")))
        XCTAssertTrue(text.contains(field("temperature", "0")))
        XCTAssertTrue(text.hasSuffix("--BOUNDARY--\r\n"))
    }

    func test_makeRequest_withPrompt_includesPrompt() {
        let text = body(makeRequest(prompt: "TalkKey、施行日"))

        XCTAssertTrue(text.contains(field("prompt", "TalkKey、施行日")))
    }

    func test_makeRequest_withoutPrompt_omitsPrompt() {
        XCTAssertFalse(body(makeRequest(prompt: "")).contains("name=\"prompt\""))
    }

    func test_makeRequest_withShortAudio_sendsAudioContext768() {
        XCTAssertTrue(body(makeRequest(duration: 14)).contains(field("audio_ctx", "768")))
    }

    func test_makeRequest_withLongAudio_omitsAudioContext() {
        XCTAssertFalse(body(makeRequest(duration: 14.1)).contains("audio_ctx"))
    }
}
