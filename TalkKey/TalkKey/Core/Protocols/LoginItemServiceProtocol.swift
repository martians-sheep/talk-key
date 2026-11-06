import Foundation

protocol LoginItemServiceProtocol: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}
