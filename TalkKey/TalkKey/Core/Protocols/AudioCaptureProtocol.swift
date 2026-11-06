import AVFoundation

protocol AudioCaptureProtocol: AnyObject {
    /// 押した瞬間に録音を始められるよう、マイクを開かずに準備だけ済ませる
    func prepare()
    func startCapture() throws
    func stopCapture()
    var audioBufferHandler: ((AVAudioPCMBuffer) -> Void)? { get set }
}
