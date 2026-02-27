import XCTest
@testable import TalkKey

final class GeminiModelTests: XCTestCase {

    // MARK: - Case count

    func testAllCasesCount() {
        XCTAssertEqual(GeminiModel.allCases.count, 5)
    }

    // MARK: - Raw value (API model ID)

    func testRawValueReturnsCorrectAPIString() {
        XCTAssertEqual(GeminiModel.gemini25Flash.rawValue, "gemini-2.5-flash")
        XCTAssertEqual(GeminiModel.gemini25FlashLite.rawValue, "gemini-2.5-flash-lite")
        XCTAssertEqual(GeminiModel.gemini20Flash.rawValue, "gemini-2.0-flash")
        XCTAssertEqual(GeminiModel.gemini25Pro.rawValue, "gemini-2.5-pro")
        XCTAssertEqual(GeminiModel.gemini3Flash.rawValue, "gemini-3-flash")
    }

    // MARK: - Display name

    func testDisplayNameReturnsJapanese() {
        for model in GeminiModel.allCases {
            let name = model.displayName
            XCTAssertFalse(name.isEmpty, "\(model) should have a display name")
        }
    }

    func testDisplayNameContainsPreviewForGemini3Flash() {
        XCTAssertTrue(GeminiModel.gemini3Flash.displayName.contains("Preview"))
    }

    // MARK: - Default model

    func testDefaultModelIsGemini25Flash() {
        XCTAssertEqual(GeminiModel.defaultModel, .gemini25Flash)
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        let original = GeminiModel.gemini25FlashLite
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GeminiModel.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
