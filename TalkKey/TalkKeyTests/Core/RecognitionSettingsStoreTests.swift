import XCTest
@testable import TalkKey

final class RecognitionSettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: RecognitionSettingsStore!

    override func setUp() {
        super.setUp()
        suiteName = "RecognitionSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = RecognitionSettingsStore(userDefaults: defaults, homeDirectory: "/Users/tester")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_load_withNothingSaved_returnsDefaults() {
        let settings = store.load()

        XCTAssertEqual(settings.engine, .whisperWithAppleFallback)
        XCTAssertEqual(settings.whisperServerURL.absoluteString, "http://127.0.0.1:8178")
        XCTAssertEqual(settings.vocabularyHint, "")
        XCTAssertEqual(settings.whisperBinaryPath, "/Users/tester/.local/src/whisper.cpp/build/bin/whisper-server")
        XCTAssertEqual(settings.whisperModelPath, "/Users/tester/.local/share/whisper/ggml-large-v3-turbo-q5_0.bin")
        XCTAssertEqual(settings.whisperVADModelPath, "/Users/tester/.local/share/whisper/ggml-silero-v6.2.0.bin")
    }

    func test_save_thenLoad_roundTrips() {
        var settings = store.load()
        settings.engine = .appleOnly
        settings.whisperServerURL = URL(string: "http://127.0.0.1:9000")!
        settings.vocabularyHint = "TalkKey、施行日"
        settings.whisperModelPath = "/models/other.bin"

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func test_load_withInvalidStoredValues_fallsBackToDefaults() {
        defaults.set("not a url", forKey: "whisperServerURL")
        defaults.set("unknown-engine", forKey: "recognitionEngine")

        let settings = store.load()

        XCTAssertEqual(settings.whisperServerURL.absoluteString, "http://127.0.0.1:8178")
        XCTAssertEqual(settings.engine, .whisperWithAppleFallback)
    }

    func test_load_withEmptyPath_usesDefaultPath() {
        defaults.set("", forKey: "whisperBinaryPath")

        XCTAssertEqual(store.load().whisperBinaryPath, "/Users/tester/.local/src/whisper.cpp/build/bin/whisper-server")
    }

    // MARK: - Derived values

    func test_vocabularyTerms_splitsOnCommasAndNewlines() {
        var settings = store.load()
        settings.vocabularyHint = " TalkKey, 施行日、新旧対照表\nAgent Board ,, "

        XCTAssertEqual(settings.vocabularyTerms, ["TalkKey", "施行日", "新旧対照表", "Agent Board"])
        XCTAssertEqual(settings.whisperPrompt, "TalkKey、施行日、新旧対照表、Agent Board")
    }

    func test_whisperServerConfiguration_usesSettingsAndOwnPort8179() {
        let settings = store.load()

        let configuration = settings.whisperServerConfiguration

        XCTAssertEqual(configuration.primaryURL, settings.whisperServerURL)
        XCTAssertEqual(configuration.ownURL.absoluteString, "http://127.0.0.1:8179")
        XCTAssertEqual(configuration.binaryPath, settings.whisperBinaryPath)
        XCTAssertEqual(configuration.modelPath, settings.whisperModelPath)
        XCTAssertEqual(configuration.vadModelPath, settings.whisperVADModelPath)
        XCTAssertEqual(configuration.threads, 8)
    }

    func test_recognitionEngine_hasDisplayNames() {
        for engine in RecognitionEngine.allCases {
            XCTAssertFalse(engine.displayName.isEmpty)
        }
    }
}
