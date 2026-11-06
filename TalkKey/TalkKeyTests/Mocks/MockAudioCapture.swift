import AVFoundation
@testable import TalkKey

final class MockAudioCapture: AudioCaptureProtocol {
    var audioBufferHandler: ((AVAudioPCMBuffer) -> Void)?

    private(set) var startCaptureCalled = false
    private(set) var stopCaptureCalled = false
    var startCaptureError: Error?
    private(set) var prepareCalled = false

    func prepare() {
        prepareCalled = true
    }

    func startCapture() throws {
        startCaptureCalled = true
        if let error = startCaptureError {
            throw error
        }
    }

    func stopCapture() {
        stopCaptureCalled = true
    }
}
