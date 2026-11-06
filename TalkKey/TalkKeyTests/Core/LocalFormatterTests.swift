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
        let result = try await formatter.format(text: "えーと今日は、あの、天気が良いです", mode: .memo)
        XCTAssertEqual(result, "今日は、天気が良いです")
    }

    // MARK: - フィラー除去（長音つきはどこでも消す）

    func test_format_withLongVowelFillersInsideSentence_removesThem() async throws {
        let result = try await formatter.format(text: "今日はえーと天気がうーん良いです", mode: .memo)
        XCTAssertEqual(result, "今日は天気が良いです")
    }

    func test_format_withFillerAtStartFollowedByComma_removesFillerAndComma() async throws {
        let cases: [(String, String)] = [
            ("あの、今日は晴れです", "今日は晴れです"),
            ("まあ、いいか", "いいか"),
            ("なんか、変だね", "変だね"),
            ("その、問題はここです", "問題はここです"),
            ("うーん、どうしよう", "どうしよう"),
            ("えー、それでは始めます", "それでは始めます"),
            ("あのー資料を見てください", "資料を見てください"),
        ]
        for (input, expected) in cases {
            let result = try await formatter.format(text: input, mode: .memo)
            XCTAssertEqual(result, expected, "input: \(input)")
        }
    }

    func test_format_withChainedFillers_removesAll() async throws {
        let result = try await formatter.format(text: "えーと、あの、なんか、それで行きましょう", mode: .memo)
        XCTAssertEqual(result, "それで行きましょう")
    }

    func test_format_withFillerSeparatedBySpace_removesFiller() async throws {
        let result = try await formatter.format(text: "あの 明日の件ですが", mode: .memo)
        XCTAssertEqual(result, "明日の件ですが")
    }

    // MARK: - フィラーに似た意味のある語は残す

    func test_format_withMeaningfulWordsResemblingFillers_keepsThem() async throws {
        let cases = [
            "あのファイルを開いて",
            "なんかの資料があった",
            "まあまあの出来です",
            "そのまま進めてください",
            "その件は了解です",
            "今日はあの店に行く",
            "それなんかいいね",
        ]
        for input in cases {
            let result = try await formatter.format(text: input, mode: .memo)
            XCTAssertEqual(result, input, "input: \(input)")
        }
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
