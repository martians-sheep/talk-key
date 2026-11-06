import Foundation

struct WhisperServerConfiguration: Equatable {
    static let defaultOwnPort = 8179
    static let defaultThreads = 8

    /// まず使う whisper-server（Agent Board が動いていれば共用する）
    var primaryURL: URL
    /// primary が応答しないとき TalkKey が自分で起動する whisper-server のポート
    var ownPort: Int
    var binaryPath: String
    var modelPath: String
    var vadModelPath: String
    var threads: Int

    var ownURL: URL {
        URL(string: "http://127.0.0.1:\(ownPort)")!
    }
}
