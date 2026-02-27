import AVFoundation

protocol TranscriberProtocol: AnyObject {
    func startTranscription() throws
    func stopTranscription() async throws -> TranscriptionResult
    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer)
    var partialResultHandler: ((String) -> Void)? { get set }
}
