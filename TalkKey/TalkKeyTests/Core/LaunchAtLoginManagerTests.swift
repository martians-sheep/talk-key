import XCTest
@testable import TalkKey

final class LaunchAtLoginManagerTests: XCTestCase {
    private var service: MockLoginItemService!
    private var logger: MockLogger!
    private var manager: LaunchAtLoginManager!

    override func setUp() {
        super.setUp()
        service = MockLoginItemService()
        logger = MockLogger()
        manager = LaunchAtLoginManager(service: service, logger: logger)
    }

    func testStatusReflectsService() {
        service.status = .enabled
        XCTAssertEqual(manager.status, .enabled)
    }

    func testToggleRegistersWhenDisabled() throws {
        service.status = .disabled
        let status = try manager.toggle()
        XCTAssertEqual(service.registerCount, 1)
        XCTAssertEqual(service.unregisterCount, 0)
        XCTAssertEqual(status, .enabled)
    }

    func testToggleUnregistersWhenEnabled() throws {
        service.status = .enabled
        let status = try manager.toggle()
        XCTAssertEqual(service.unregisterCount, 1)
        XCTAssertEqual(status, .disabled)
    }

    func testToggleUnregistersWhenApprovalIsPending() throws {
        // 登録はしたが、システム設定で承認待ちのときにもう一度押したら、登録をやめる
        service.status = .requiresApproval
        let status = try manager.toggle()
        XCTAssertEqual(service.unregisterCount, 1)
        XCTAssertEqual(status, .disabled)
    }

    func testToggleReturnsRequiresApprovalWhenSystemAsksForApproval() throws {
        service.status = .disabled
        service.statusAfterRegister = .requiresApproval
        XCTAssertEqual(try manager.toggle(), .requiresApproval)
    }

    func testToggleLogsAndRethrowsOnFailure() {
        service.status = .disabled
        service.errorToThrow = TalkKeyError.permissionDenied("not allowed")
        XCTAssertThrowsError(try manager.toggle())
        XCTAssertEqual(logger.lastLevel, .error)
    }
}
