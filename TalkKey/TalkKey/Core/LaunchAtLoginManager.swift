import Foundation

/// ログイン時に TalkKey を起動するかを切り替える
final class LaunchAtLoginManager {
    private let service: LoginItemServiceProtocol
    private let logger: LoggerProtocol

    init(service: LoginItemServiceProtocol = SystemLoginItemService(), logger: LoggerProtocol = FileLogger.shared) {
        self.service = service
        self.logger = logger
    }

    var status: LoginItemStatus {
        service.status
    }

    /// オフなら登録し、オン（承認待ちを含む）なら登録をやめる。切り替えたあとの状態を返す
    @discardableResult
    func toggle() throws -> LoginItemStatus {
        do {
            if service.status == .disabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            logger.error("Launch at login change failed: \(error.localizedDescription)")
            throw error
        }
        logger.info("Launch at login: \(service.status)")
        return service.status
    }
}
