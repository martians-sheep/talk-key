import Foundation

struct RecognitionSettings: Equatable {
    var engine: RecognitionEngine
    var whisperServerURL: URL
    /// 用語のヒント。読点・カンマ・改行で区切る
    var vocabularyHint: String
    var whisperBinaryPath: String
    var whisperModelPath: String
    var whisperVADModelPath: String

    var vocabularyTerms: [String] {
        vocabularyHint
            .components(separatedBy: CharacterSet(charactersIn: ",、，\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var whisperPrompt: String {
        vocabularyTerms.joined(separator: "、")
    }

    var whisperServerConfiguration: WhisperServerConfiguration {
        WhisperServerConfiguration(
            primaryURL: whisperServerURL,
            ownPort: WhisperServerConfiguration.defaultOwnPort,
            binaryPath: whisperBinaryPath,
            modelPath: whisperModelPath,
            vadModelPath: whisperVADModelPath,
            threads: WhisperServerConfiguration.defaultThreads
        )
    }
}
