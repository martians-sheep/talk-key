import XCTest
@testable import TalkKey

final class InserterTests: XCTestCase {
    private var pasteboardProvider: MockPasteboardProvider!
    private var keyEventSender: MockKeyEventSender!
    private var operationTracker: OperationTracker!
    private var inserter: Inserter!

    override func setUp() {
        super.setUp()
        operationTracker = OperationTracker()
        pasteboardProvider = MockPasteboardProvider(tracker: operationTracker)
        keyEventSender = MockKeyEventSender(tracker: operationTracker)
        inserter = Inserter(
            pasteboardProvider: pasteboardProvider,
            keyEventSender: keyEventSender,
            restoreDelay: 0.0
        )
    }

    // MARK: - 1.5-1 Tests

    func testInsertSetTextToPasteboard() async throws {
        try await inserter.insert(text: "テスト")
        XCTAssertEqual(pasteboardProvider.lastSetText, "テスト")
    }

    func testInsertBackupsPasteboardBeforeInsertion() async throws {
        pasteboardProvider.currentItems = [
            PasteboardItem(type: "public.utf8-plain-text", data: Data("original".utf8))
        ]
        try await inserter.insert(text: "new text")
        XCTAssertTrue(pasteboardProvider.backupCalled)
        XCTAssertTrue(pasteboardProvider.backupCalledBeforeSet)
    }

    func testInsertRestoresPasteboardAfterInsertion() async throws {
        pasteboardProvider.currentItems = [
            PasteboardItem(type: "public.utf8-plain-text", data: Data("original".utf8))
        ]
        try await inserter.insert(text: "new text")
        XCTAssertTrue(pasteboardProvider.restoreCalled)
    }

    func testInsertOperationOrder() async throws {
        pasteboardProvider.currentItems = [
            PasteboardItem(type: "public.utf8-plain-text", data: Data("original".utf8))
        ]
        try await inserter.insert(text: "test")
        XCTAssertEqual(operationTracker.log, ["backup", "setText", "sendCmdV", "restore"])
    }

    func testInsertPreservesMultiplePasteboardTypes() async throws {
        pasteboardProvider.currentItems = [
            PasteboardItem(type: "public.utf8-plain-text", data: Data("text".utf8)),
            PasteboardItem(type: "public.png", data: Data([0x89, 0x50, 0x4E, 0x47]))
        ]
        try await inserter.insert(text: "new")
        XCTAssertEqual(pasteboardProvider.backedUpItems?.count, 2)
        XCTAssertEqual(pasteboardProvider.restoredItems?.count, 2)
    }

    func testInsertSkipsEmptyText() async throws {
        try await inserter.insert(text: "")
        XCTAssertFalse(pasteboardProvider.setTextCalled)
        XCTAssertFalse(keyEventSender.sendCalled)
    }

    func testDefaultRestoreDelayWaitsForSlowApps() {
        // VS Code・Chrome・Slack などはペーストを遅れて読むため、0.1秒で戻すと元の内容が貼られる
        XCTAssertGreaterThanOrEqual(Inserter.defaultRestoreDelay, 0.5)
    }

    func testInsertDoesNotRestoreWhenPasteboardChangedDuringDelay() async throws {
        pasteboardProvider.currentItems = [
            PasteboardItem(type: "public.utf8-plain-text", data: Data("original".utf8))
        ]
        // 貼り付けのあと、戻す前に利用者が別の内容をコピーした
        keyEventSender.onSend = { [pasteboardProvider] in pasteboardProvider?.simulateExternalCopy() }
        try await inserter.insert(text: "new text")
        XCTAssertFalse(pasteboardProvider.restoreCalled)
    }

    func testInsertLeavesTextInPasteboardOnCmdVFailure() async throws {
        keyEventSender.shouldFail = true
        do {
            try await inserter.insert(text: "recovery text")
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(pasteboardProvider.lastSetText, "recovery text")
            XCTAssertFalse(pasteboardProvider.restoreCalled)
        }
    }
}

// MARK: - Shared Operation Tracker

final class OperationTracker {
    private(set) var log: [String] = []

    func record(_ operation: String) {
        log.append(operation)
    }
}

// MARK: - Mock Pasteboard Provider

final class MockPasteboardProvider: PasteboardProviderProtocol {
    var currentItems: [PasteboardItem] = []
    private(set) var backupCalled = false
    private(set) var setTextCalled = false
    private(set) var restoreCalled = false
    private(set) var lastSetText: String?
    private(set) var backedUpItems: [PasteboardItem]?
    private(set) var restoredItems: [PasteboardItem]?
    private(set) var backupCalledBeforeSet = false
    private(set) var changeCount = 0

    private let tracker: OperationTracker

    init(tracker: OperationTracker) {
        self.tracker = tracker
    }

    func backup() -> [PasteboardItem] {
        backupCalled = true
        backedUpItems = currentItems
        tracker.record("backup")
        return currentItems
    }

    func setText(_ text: String) {
        if backupCalled && !setTextCalled {
            backupCalledBeforeSet = true
        }
        setTextCalled = true
        lastSetText = text
        changeCount += 1
        tracker.record("setText")
    }

    func simulateExternalCopy() {
        changeCount += 1
    }

    func restore(items: [PasteboardItem]) {
        restoreCalled = true
        restoredItems = items
        tracker.record("restore")
    }
}

// MARK: - Mock Key Event Sender

final class MockKeyEventSender: KeyEventSenderProtocol {
    private(set) var sendCalled = false
    var shouldFail = false
    var onSend: (() -> Void)?

    private let tracker: OperationTracker

    init(tracker: OperationTracker) {
        self.tracker = tracker
    }

    func sendCmdV() throws {
        sendCalled = true
        tracker.record("sendCmdV")
        onSend?()
        if shouldFail {
            throw TalkKeyError.insertionFailed("Cmd+V send failed")
        }
    }
}
