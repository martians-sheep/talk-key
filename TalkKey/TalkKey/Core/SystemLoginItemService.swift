import ServiceManagement

/// SMAppService.mainApp で、このアプリ自体をログイン項目に登録する
final class SystemLoginItemService: LoginItemServiceProtocol {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        default:
            return .disabled
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
