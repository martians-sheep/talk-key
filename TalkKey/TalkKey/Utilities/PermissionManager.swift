import AppKit

enum PermissionStatus: Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

protocol PermissionCheckerProtocol {
    func checkMicrophonePermission() -> PermissionStatus
    func checkSpeechRecognitionPermission() -> PermissionStatus
    func checkAccessibilityPermission() -> Bool
    func requestAccessibilityAccess() -> Bool
    func requestMicrophoneAccess() async -> Bool
    func requestSpeechRecognitionAccess() async -> Bool
}

final class PermissionManager {
    private let checker: PermissionCheckerProtocol

    init(checker: PermissionCheckerProtocol) {
        self.checker = checker
    }

    var microphoneStatus: PermissionStatus {
        checker.checkMicrophonePermission()
    }

    var speechRecognitionStatus: PermissionStatus {
        checker.checkSpeechRecognitionPermission()
    }

    var accessibilityStatus: Bool {
        checker.checkAccessibilityPermission()
    }

    var allPermissionsGranted: Bool {
        microphoneStatus == .authorized
            && speechRecognitionStatus == .authorized
            && accessibilityStatus
    }

    func requestMicrophoneAccess() async -> Bool {
        await checker.requestMicrophoneAccess()
    }

    func requestSpeechRecognitionAccess() async -> Bool {
        await checker.requestSpeechRecognitionAccess()
    }

    func openAccessibilitySettings() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let settingsURL = URL(string: url) {
            NSWorkspace.shared.open(settingsURL)
        }
    }
}
