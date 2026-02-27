import AVFoundation
@testable import TalkKey

final class MockTranscriber: TranscriberProtocol {
    var partialResultHandler: ((String) -> Void)?

    private(set) var startTranscriptionCalled = false
    private(set) var stopTranscriptionCalled = false
    private(set) var fedBuffers: [AVAudioPCMBuffer] = []
    var startTranscriptionError: Error?
    var transcriptionResult = TranscriptionResult(
        rawText: "mock transcription",
        formattedText: nil,
        timestamp: Date(),
        duration: 1.0
    )

    func startTranscription() throws {
        startTranscriptionCalled = true
        if let error = startTranscriptionError {
            throw error
        }
    }

    func stopTranscription() async throws -> TranscriptionResult {
        stopTranscriptionCalled = true
        return transcriptionResult
    }

    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        fedBuffers.append(buffer)
    }
}
