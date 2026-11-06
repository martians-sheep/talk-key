@testable import TalkKey

final class MockLoginItemService: LoginItemServiceProtocol {
    var status: LoginItemStatus = .disabled
    var statusAfterRegister: LoginItemStatus = .enabled
    var errorToThrow: Error?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    func register() throws {
        if let errorToThrow { throw errorToThrow }
        registerCount += 1
        status = statusAfterRegister
    }

    func unregister() throws {
        if let errorToThrow { throw errorToThrow }
        unregisterCount += 1
        status = .disabled
    }
}
