import Foundation

protocol FormatterProtocol {
    func format(text: String, mode: FormattingMode) async throws -> String
}
