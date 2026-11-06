import Foundation

protocol RecognitionSettingsStoreProtocol {
    func load() -> RecognitionSettings
    func save(_ settings: RecognitionSettings)
}
