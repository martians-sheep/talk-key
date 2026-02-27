import AVFoundation

protocol AudioCaptureProtocol: AnyObject {
    func startCapture() throws
    func stopCapture()
    var audioBufferHandler: ((AVAudioPCMBuffer) -> Void)? { get set }
}
