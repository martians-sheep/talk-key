import XCTest
import AVFoundation
@testable import TalkKey

final class AudioCaptureTests: XCTestCase {
    private var permissionChecker: MockPermissionCheckerForAudio!
    private var audioEngineProvider: MockAudioEngineProvider!
    private var audioCapture: AudioCapture!
    private var logger: MockLogger!

    override func setUp() {
        super.setUp()
        permissionChecker = MockPermissionCheckerForAudio()
        permissionChecker.micGranted = true
        audioEngineProvider = MockAudioEngineProvider()
        logger = MockLogger()
        audioCapture = AudioCapture(
            permissionChecker: permissionChecker,
            engineProvider: audioEngineProvider,
            logger: logger
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

// MARK: - Warm-up and latency

extension AudioCaptureTests {
    func test_prepare_withMicPermission_preparesEngine() {
        audioCapture.prepare()

        XCTAssertEqual(audioEngineProvider.prepareCallCount, 1)
    }

    func test_prepare_withoutMicPermission_doesNotTouchEngine() {
        permissionChecker.micGranted = false

        audioCapture.prepare()

        XCTAssertEqual(audioEngineProvider.prepareCallCount, 0)
    }

    func test_startCapture_logsLatencyUntilFirstBufferOnlyOnce() throws {
        try audioCapture.startCapture()

        audioEngineProvider.simulateBuffer(TestAudioBuffers.sine(duration: 0.1))
        audioEngineProvider.simulateBuffer(TestAudioBuffers.sine(duration: 0.1))

        let latencyLogs = logger.loggedMessages.filter { $0.message.contains("First audio buffer") }
        XCTAssertEqual(latencyLogs.count, 1)
        XCTAssertTrue(latencyLogs.first?.message.contains("ms") ?? false)
    }

    func test_startCapture_eachRecordingLogsItsOwnFirstBufferLatency() throws {
        try audioCapture.startCapture()
        audioEngineProvider.simulateBuffer(TestAudioBuffers.sine(duration: 0.1))
        audioCapture.stopCapture()

        try audioCapture.startCapture()
        audioEngineProvider.simulateBuffer(TestAudioBuffers.sine(duration: 0.1))

        XCTAssertEqual(logger.loggedMessages.filter { $0.message.contains("First audio buffer") }.count, 2)
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
