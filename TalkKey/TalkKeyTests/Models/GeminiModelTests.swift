import XCTest
@testable import TalkKey

final class GeminiModelTests: XCTestCase {

    // MARK: - Raw value (API model ID)

    func testRawValueReturnsCorrectAPIString() {
        XCTAssertEqual(GeminiModel.gemini38Flash.rawValue, "gemini-3.8-flash")
        XCTAssertEqual(GeminiModel.gemini35FlashLite.rawValue, "gemini-3.5-flash-lite")
        XCTAssertEqual(GeminiModel.geminiFlashLatest.rawValue, "gemini-flash-latest")
        XCTAssertEqual(GeminiModel.geminiFlashLiteLatest.rawValue, "gemini-flash-lite-latest")
    }

    func test_allCases_doNotContainRetiredModels() {
        let rawValues = GeminiModel.allCases.map(\.rawValue)
        XCTAssertFalse(rawValues.contains { $0.hasPrefix("gemini-2.") })
    }

    // MARK: - Display name

    func testDisplayNameReturnsJapanese() {
        for model in GeminiModel.allCases {
            let name = model.displayName
            XCTAssertFalse(name.isEmpty, "\(model) should have a display name")
        }
    }

    // MARK: - Default model

    func test_defaultModel_isGemini38Flash() {
        XCTAssertEqual(GeminiModel.defaultModel, .gemini38Flash)
    }

    // MARK: - Stored value migration

    func test_fromStoredValue_withCurrentModel_returnsThatModel() {
        XCTAssertEqual(GeminiModel(storedValue: "gemini-3.5-flash-lite"), .gemini35FlashLite)
    }

    func test_fromStoredValue_withRetiredModel_returnsDefault() {
        for retired in ["gemini-2.0-flash", "gemini-2.5-flash", "gemini-2.5-pro", "gemini-3-flash"] {
            XCTAssertEqual(GeminiModel(storedValue: retired), .defaultModel, retired)
        }
    }

    func test_fromStoredValue_withNil_returnsDefault() {
        XCTAssertEqual(GeminiModel(storedValue: nil), .defaultModel)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = GeminiModel.gemini35FlashLite
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GeminiModel.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
