@testable import TalkKey
import XCTest

final class KeychainHelperTests: XCTestCase {
    private let testService = "com.talkkey.test.\(UUID().uuidString)"

    override func tearDown() {
        // Clean up any test keys
        try? KeychainHelper(service: testService).delete(key: "apiKey")
        super.tearDown()
    }

    func test_save_canSaveAPIKey() throws {
        let helper = KeychainHelper(service: testService)

        try helper.save(key: "apiKey", value: "test-api-key-123")

        let retrieved = try helper.load(key: "apiKey")
        XCTAssertEqual(retrieved, "test-api-key-123")
    }

    func test_load_returnsValueForExistingKey() throws {
        let helper = KeychainHelper(service: testService)
        try helper.save(key: "apiKey", value: "my-secret-key")

        let value = try helper.load(key: "apiKey")
        XCTAssertEqual(value, "my-secret-key")
    }

    func test_delete_removesKeyFromKeychain() throws {
        let helper = KeychainHelper(service: testService)
        try helper.save(key: "apiKey", value: "to-be-deleted")

        try helper.delete(key: "apiKey")

        let value = try helper.load(key: "apiKey")
        XCTAssertNil(value)
    }

    func test_load_returnsNilForNonExistentKey() throws {
        let helper = KeychainHelper(service: testService)

        let value = try helper.load(key: "nonexistent")
        XCTAssertNil(value)
    }
}
