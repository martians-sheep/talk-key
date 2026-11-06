import AVFoundation
@testable import TalkKey

final class MockSpeechRecognizerProvider: SpeechRecognizerProviderProtocol {
    var requestedLocale: Locale?
    private(set) var requestedContextualStrings: [String] = []
    var shouldFailOnStart = false
    var onDeviceAvailable = true
    private(set) var cancelCalled = false
    private(set) var finishAudioCalled = false
    private(set) var callOrder: [String] = []
    private(set) var fedBuffers: [AVAudioPCMBuffer] = []

    // finishAudio の後、別スレッドから非同期に届ける最終結果・エラー（実機の SFSpeechRecognizer の振る舞いを模す）
    var finalTextDeliveredAfterFinish: String?
    var errorDeliveredAfterFinish: Error?

    private var resultHandler: ((String, Bool) -> Void)?
    private var errorHandler: ((Error) -> Void)?
    private var previousErrorHandler: ((Error) -> Void)?

    var supportsOnDeviceRecognition: Bool { onDeviceAvailable }

    func startRecognition(
        locale: Locale,
        contextualStrings: [String],
        resultHandler: @escaping (String, Bool) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) throws {
        if shouldFailOnStart {
            throw TalkKeyError.transcriptionFailed("Speech recognition failed to start")
        }
        callOrder.append("start")
        requestedLocale = locale
        requestedContextualStrings = contextualStrings
        self.resultHandler = resultHandler
        self.errorHandler = errorHandler
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        fedBuffers.append(buffer)
    }

    func finishAudio() {
        finishAudioCalled = true
        callOrder.append("finishAudio")
        let resultHandler = self.resultHandler
        let errorHandler = self.errorHandler
        if let text = finalTextDeliveredAfterFinish {
            DispatchQueue.global().async { resultHandler?(text, true) }
        }
        if let error = errorDeliveredAfterFinish {
            DispatchQueue.global().async { errorHandler?(error) }
        }
    }

    func cancelRecognition() {
        cancelCalled = true
        callOrder.append("cancel")
        previousErrorHandler = errorHandler
        resultHandler = nil
        errorHandler = nil
    }

    func simulateResult(text: String, isFinal: Bool) {
        resultHandler?(text, isFinal)
    }

    func simulateError(_ error: Error) {
        errorHandler?(error)
    }

    func simulateStaleError(_ error: Error) {
        previousErrorHandler?(error)
    }
}
