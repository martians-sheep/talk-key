import Foundation

/// 実際に文字起こしを行ったエンジン
enum RecognitionSource: String, Codable {
    case whisper
    case apple
}
