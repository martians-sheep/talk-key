import Foundation

enum ServiceStatus: Equatable {
    case idle
    case recording
    case processing
    case inserting
    case error(String)
}
