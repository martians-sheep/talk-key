import XCTest
@testable import TalkKey

final class PermissionManagerTests: XCTestCase {
    func testAllPermissionsGranted() {
        let checker = MockPermissionChecker(
            microphoneStatus: .authorized,
            speechRecognitionStatus: .authorized,
            accessibilityGranted: true
        )
        let manager = PermissionManager(checker: checker)

        XCTAssertEqual(manager.microphoneStatus, .authorized)
        XCTAssertEqual(manager.speechRecognitionStatus, .authorized)
        XCTAssertTrue(manager.accessibilityStatus)
        XCTAssertTrue(manager.allPermissionsGranted)
    }

    func testMicrophoneDenied() {
        let checker = MockPermissionChecker(
            microphoneStatus: .denied,
            speechRecognitionStatus: .authorized,
            accessibilityGranted: true
        )
        let manager = PermissionManager(checker: checker)

        XCTAssertEqual(manager.microphoneStatus, .denied)
        XCTAssertFalse(manager.allPermissionsGranted)
    }

    func testSpeechRecognitionNotDetermined() {
        let checker = MockPermissionChecker(
            microphoneStatus: .authorized,
            speechRecognitionStatus: .notDetermined,
            accessibilityGranted: true
        )
        let manager = PermissionManager(checker: checker)

        XCTAssertEqual(manager.speechRecognitionStatus, .notDetermined)
        XCTAssertFalse(manager.allPermissionsGranted)
    }

    func testAccessibilityDenied() {
        let checker = MockPermissionChecker(
            microphoneStatus: .authorized,
            speechRecognitionStatus: .authorized,
            accessibilityGranted: false
        )
        let manager = PermissionManager(checker: checker)

        XCTAssertFalse(manager.accessibilityStatus)
        XCTAssertFalse(manager.allPermissionsGranted)
    }

    func testRequestMicrophonePermission() async {
        let checker = MockPermissionChecker(
            microphoneStatus: .notDetermined,
            speechRecognitionStatus: .authorized,
            accessibilityGranted: true
        )
        let manager = PermissionManager(checker: checker)

        let granted = await manager.requestMicrophoneAccess()
        XCTAssertTrue(granted)
        XCTAssertTrue(checker.microphoneRequested)
    }

    func testRequestSpeechRecognitionPermission() async {
        let checker = MockPermissionChecker(
            microphoneStatus: .authorized,
            speechRecognitionStatus: .notDetermined,
            accessibilityGranted: true
        )
        let manager = PermissionManager(checker: checker)

        let granted = await manager.requestSpeechRecognitionAccess()
        XCTAssertTrue(granted)
        XCTAssertTrue(checker.speechRecognitionRequested)
    }
}

// MARK: - MockPermissionChecker

final class MockPermissionChecker: PermissionCheckerProtocol {
    var microphoneStatus: PermissionStatus
    var speechRecognitionStatus: PermissionStatus
    var accessibilityGranted: Bool
    private(set) var microphoneRequested = false
    private(set) var speechRecognitionRequested = false

    init(
        microphoneStatus: PermissionStatus,
        speechRecognitionStatus: PermissionStatus,
        accessibilityGranted: Bool
    ) {
        self.microphoneStatus = microphoneStatus
        self.speechRecognitionStatus = speechRecognitionStatus
        self.accessibilityGranted = accessibilityGranted
    }

    func checkMicrophonePermission() -> PermissionStatus {
        microphoneStatus
    }

    func checkSpeechRecognitionPermission() -> PermissionStatus {
        speechRecognitionStatus
    }

    func checkAccessibilityPermission() -> Bool {
        accessibilityGranted
    }

    func requestAccessibilityAccess() -> Bool {
        accessibilityGranted
    }

    func requestMicrophoneAccess() async -> Bool {
        microphoneRequested = true
        return true
    }

    func requestSpeechRecognitionAccess() async -> Bool {
        speechRecognitionRequested = true
        return true
    }
}
