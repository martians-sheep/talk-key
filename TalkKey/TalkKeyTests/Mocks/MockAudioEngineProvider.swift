import AVFoundation
@testable import TalkKey

final class MockAudioEngineProvider: AudioEngineProviderProtocol {
    private(set) var startCalled = false
    private(set) var stopCalled = false
    private(set) var prepareCallCount = 0
    private var bufferHandler: ((AVAudioPCMBuffer) -> Void)?

    func prepare() throws {
        prepareCallCount += 1
    }

    func start(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) throws {
        startCalled = true
        self.bufferHandler = bufferHandler
    }

    func stop() {
        stopCalled = true
        bufferHandler = nil
    }

    func simulateBuffer(_ buffer: AVAudioPCMBuffer) {
        bufferHandler?(buffer)
    }
}
