import Foundation

protocol LoggerProtocol {
    func log(_ level: LogLevel, _ message: String)
}

extension LoggerProtocol {
    func debug(_ message: String) { log(.debug, message) }
    func info(_ message: String) { log(.info, message) }
    func warning(_ message: String) { log(.warning, message) }
    func error(_ message: String) { log(.error, message) }
}
