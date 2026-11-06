import Foundation

protocol WhisperServerProviderProtocol: AnyObject {
    /// 今すぐ使える whisper-server の URL。使えなければ nil（待たせない）
    func readyServerURL() async -> URL?
}
