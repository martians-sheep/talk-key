import AVFoundation

protocol AudioEngineProviderProtocol: AnyObject {
    func start(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) throws
    func stop()
}

final class AudioCapture: AudioCaptureProtocol {
    var audioBufferHandler: ((AVAudioPCMBuffer) -> Void)?

    private let permissionChecker: PermissionCheckerProtocol
    private let engineProvider: AudioEngineProviderProtocol
    private var isCapturing = false

    init(
        permissionChecker: PermissionCheckerProtocol,
        engineProvider: AudioEngineProviderProtocol = SystemAudioEngineProvider()
    ) {
        self.permissionChecker = permissionChecker
        self.engineProvider = engineProvider
    }

    func startCapture() throws {
        guard permissionChecker.checkMicrophonePermission() == .authorized else {
            throw TalkKeyError.permissionDenied("Microphone permission is required")
        }
        guard !isCapturing else { return }

        try engineProvider.start { [weak self] buffer in
            self?.audioBufferHandler?(buffer)
        }
        isCapturing = true
    }

    func stopCapture() {
        guard isCapturing else { return }
        engineProvider.stop()
        isCapturing = false
    }
}

final class SystemAudioEngineProvider: AudioEngineProviderProtocol {
    private let engine = AVAudioEngine()
    private let bufferSize: AVAudioFrameCount = 1024

    func start(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
            bufferHandler(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
