import XCTest
import AVFoundation
@testable import TalkKey

final class AudioCaptureTests: XCTestCase {
    private var permissionChecker: MockPermissionCheckerForAudio!
    private var audioEngineProvider: MockAudioEngineProvider!
    private var audioCapture: AudioCapture!

    override func setUp() {
        super.setUp()
        permissionChecker = MockPermissionCheckerForAudio()
        permissionChecker.micGranted = true
        audioEngineProvider = MockAudioEngineProvider()
        audioCapture = AudioCapture(
            permissionChecker: permissionChecker,
            engineProvider: audioEngineProvider
        )
    }

    override func tearDown() {
        audioCapture.stopCapture()
        audioCapture = nil
        audioEngineProvider = nil
        permissionChecker = nil
        super.tearDown()
    }

    func testStartCaptureChangesToRecordingState() throws {
        try audioCapture.startCapture()
        XCTAssertTrue(audioEngineProvider.startCalled)
    }

    func testStopCaptureStopsEngine() throws {
        try audioCapture.startCapture()
        audioCapture.stopCapture()
        XCTAssertTrue(audioEngineProvider.stopCalled)
    }

    func testAudioBufferHandlerReceivesBuffers() throws {
        var receivedBuffers: [AVAudioPCMBuffer] = []
        audioCapture.audioBufferHandler = { buffer in
            receivedBuffers.append(buffer)
        }
        try audioCapture.startCapture()

        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        audioEngineProvider.simulateBuffer(buffer)

        XCTAssertEqual(receivedBuffers.count, 1)
    }

    func testStartCaptureThrowsWithoutMicPermission() {
        permissionChecker.micGranted = false
        XCTAssertThrowsError(try audioCapture.startCapture()) { error in
            guard let tkError = error as? TalkKeyError else {
                XCTFail("Expected TalkKeyError")
                return
            }
            if case .permissionDenied(let detail) = tkError {
                XCTAssertTrue(detail.contains("Microphone"))
            } else {
                XCTFail("Expected permissionDenied error")
            }
        }
    }
}

// MARK: - Mocks

private final class MockPermissionCheckerForAudio: PermissionCheckerProtocol {
    var micGranted = true

    func checkMicrophonePermission() -> PermissionStatus {
        micGranted ? .authorized : .denied
    }
    func checkSpeechRecognitionPermission() -> PermissionStatus { .authorized }
    func checkAccessibilityPermission() -> Bool { true }
    func requestAccessibilityAccess() -> Bool { true }
    func requestMicrophoneAccess() async -> Bool { true }
    func requestSpeechRecognitionAccess() async -> Bool { true }
}

final class MockAudioEngineProvider: AudioEngineProviderProtocol {
    private(set) var startCalled = false
    private(set) var stopCalled = false
    private var bufferHandler: ((AVAudioPCMBuffer) -> Void)?

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
