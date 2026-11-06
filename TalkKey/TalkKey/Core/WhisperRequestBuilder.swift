import Foundation

enum WhisperRequestBuilder {
    // audio_ctx を声の長さぎりぎりまで下げると幻聴して遅くなったため、約15秒ぶんより下げない
    static let shortAudioContext = 768
    static let shortAudioMaxDuration: TimeInterval = 14

    static func makeRequest(
        serverURL: URL,
        wavData: Data,
        audioDuration: TimeInterval,
        prompt: String,
        timeout: TimeInterval,
        boundary: String = UUID().uuidString
    ) -> URLRequest {
        var request = URLRequest(url: serverURL.appendingPathComponent("inference"))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var fields: [(String, String)] = [
            ("language", "ja"),
            ("response_format", "json"),
            ("temperature", "0"),
        ]
        if !prompt.isEmpty {
            fields.append(("prompt", prompt))
        }
        // 短い声は処理する範囲を絞ると約2倍速くなる。長い声に付けると末尾が切れるので付けない
        if audioDuration <= shortAudioMaxDuration {
            fields.append(("audio_ctx", String(shortAudioContext)))
        }

        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wavData)
        body.append(Data("\r\n".utf8))
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data(value.utf8))
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return request
    }
}
