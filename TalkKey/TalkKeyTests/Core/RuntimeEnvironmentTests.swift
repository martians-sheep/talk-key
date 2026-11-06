import XCTest
@testable import TalkKey

final class RuntimeEnvironmentTests: XCTestCase {
    func test_isRunningTests_withXCTestConfiguration_returnsTrue() {
        XCTAssertTrue(RuntimeEnvironment.isRunningTests(environment: ["XCTestConfigurationFilePath": "/tmp/x"]))
    }

    func test_isRunningTests_withoutXCTestConfiguration_returnsFalse() {
        XCTAssertFalse(RuntimeEnvironment.isRunningTests(environment: [:]))
    }

    func test_defaultLogDirectory_underTests_isTemporaryNotUserLogs() {
        let directory = FileLogger.defaultDirectory(environment: ["XCTestConfigurationFilePath": "/tmp/x"])

        XCTAssertFalse(directory.path.contains("Library/Logs/TalkKey"))
        XCTAssertTrue(directory.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }

    func test_defaultLogDirectory_inApp_isUserLogs() {
        let directory = FileLogger.defaultDirectory(environment: [:])

        XCTAssertTrue(directory.path.hasSuffix("Library/Logs/TalkKey"))
    }
}
