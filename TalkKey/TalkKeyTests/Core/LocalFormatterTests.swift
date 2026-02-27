import XCTest
@testable import TalkKey

final class LocalFormatterTests: XCTestCase {

    private var formatter: LocalFormatter!

    override func setUp() {
        super.setUp()
        formatter = LocalFormatter()
    }

    // MARK: - 空白正規化

    func testTrimsLeadingAndTrailingWhitespace() async throws {
        let result = try await formatter.format(text: "  こんにちは  ", mode: .memo)
        XCTAssertEqual(result, "こんにちは")
    }

    func testNormalizesConsecutiveSpacesToSingle() async throws {
        let result = try await formatter.format(text: "今日は   天気が  良い", mode: .memo)
        XCTAssertEqual(result, "今日は 天気が 良い")
    }

    // MARK: - フィラー除去

    func testRemovesFillerWords() async throws {
        let result = try await formatter.format(text: "えーと今日はあの天気が良いです", mode: .memo)
        XCTAssertEqual(result, "今日は天気が良いです")
    }

    func testFillerRemovalPreservesMeaningfulWords() async throws {
        // 「あのね」は複合語として残すべき
        let result = try await formatter.format(text: "あのね、聞いてよ", mode: .memo)
        XCTAssertEqual(result, "あのね、聞いてよ")
    }

    // MARK: - 句読点正規化

    func testNormalizesDuplicatePunctuation() async throws {
        let result = try await formatter.format(text: "すごい。。本当？？", mode: .memo)
        XCTAssertEqual(result, "すごい。本当？")
    }

    // MARK: - 改行正規化

    func testRemovesUnnecessaryNewlines() async throws {
        let result = try await formatter.format(text: "こんにちは\n\n\nさようなら", mode: .memo)
        XCTAssertEqual(result, "こんにちは\nさようなら")
    }

    // MARK: - エッジケース

    func testEmptyStringReturnsEmpty() async throws {
        let result = try await formatter.format(text: "", mode: .memo)
        XCTAssertEqual(result, "")
    }

    func testPreservesProperNounsAndNumbers() async throws {
        let result = try await formatter.format(text: "田中太郎さんの電話番号は090-1234-5678です", mode: .memo)
        XCTAssertEqual(result, "田中太郎さんの電話番号は090-1234-5678です")
    }
}
