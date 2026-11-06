import XCTest
@testable import TalkKey

final class LLMProviderTests: XCTestCase {
    func test_defaultProvider_isClaude() {
        XCTAssertEqual(LLMProvider.defaultProvider, .claude)
    }

    func test_initStoredValue_withUnknownOrNil_returnsDefault() {
        XCTAssertEqual(LLMProvider(storedValue: nil), .claude)
        XCTAssertEqual(LLMProvider(storedValue: "openai"), .claude)
        XCTAssertEqual(LLMProvider(storedValue: "gemini"), .gemini)
    }

    func test_keychainAccounts_matchStoredKeys() {
        XCTAssertEqual(LLMProvider.claude.keychainAccount, "anthropicApiKey")
        XCTAssertEqual(LLMProvider.gemini.keychainAccount, "apiKey")
    }

    func test_displayName_isNotEmpty() {
        for provider in LLMProvider.allCases {
            XCTAssertFalse(provider.displayName.isEmpty)
        }
    }
}
