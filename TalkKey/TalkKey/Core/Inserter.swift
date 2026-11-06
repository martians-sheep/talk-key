import AppKit

protocol PasteboardProviderProtocol: AnyObject {
    /// 内容が書き換わるたびに増える番号。戻す前に、ほかのアプリや利用者が書き換えていないかを見る
    var changeCount: Int { get }
    func backup() -> [PasteboardItem]
    func setText(_ text: String)
    func restore(items: [PasteboardItem])
}

protocol KeyEventSenderProtocol: AnyObject {
    func sendCmdV() throws
}

final class Inserter: InserterProtocol {
    /// 貼り付けてからクリップボードを元に戻すまでの待ち時間。VS Code・Chrome・Slack などは
    /// ペーストを遅れて読むため、短いと元の内容が貼られてしまう
    static let defaultRestoreDelay: TimeInterval = 0.5

    private let pasteboardProvider: PasteboardProviderProtocol
    private let keyEventSender: KeyEventSenderProtocol
    private let restoreDelay: TimeInterval
    private let logger: LoggerProtocol

    init(
        pasteboardProvider: PasteboardProviderProtocol = SystemPasteboardProvider(),
        keyEventSender: KeyEventSenderProtocol = SystemKeyEventSender(),
        restoreDelay: TimeInterval = Inserter.defaultRestoreDelay,
        logger: LoggerProtocol = FileLogger.shared
    ) {
        self.pasteboardProvider = pasteboardProvider
        self.keyEventSender = keyEventSender
        self.restoreDelay = restoreDelay
        self.logger = logger
    }

    func insert(text: String) async throws {
        guard !text.isEmpty else { return }

        logger.debug("Inserting text (\(text.count) chars)")
        let backedUpItems = pasteboardProvider.backup()
        pasteboardProvider.setText(text)
        let insertedChangeCount = pasteboardProvider.changeCount

        do {
            try keyEventSender.sendCmdV()
        } catch {
            logger.error("Cmd+V failed: \(error.localizedDescription)")
            throw error
        }

        if restoreDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(restoreDelay * 1_000_000_000))
        }

        // 待っている間にほかの内容がコピーされていたら、そちらを残す
        guard pasteboardProvider.changeCount == insertedChangeCount else {
            logger.debug("Text inserted, clipboard changed meanwhile; not restored")
            return
        }
        pasteboardProvider.restore(items: backedUpItems)
        logger.debug("Text inserted, clipboard restored")
    }
}

// MARK: - System Implementations

final class SystemPasteboardProvider: PasteboardProviderProtocol {
    private let pasteboard = NSPasteboard.general

    var changeCount: Int { pasteboard.changeCount }

    func backup() -> [PasteboardItem] {
        var items: [PasteboardItem] = []
        guard let types = pasteboard.types else { return items }
        for type in types {
            if let data = pasteboard.data(forType: type) {
                items.append(PasteboardItem(type: type.rawValue, data: data))
            }
        }
        return items
    }

    func setText(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func restore(items: [PasteboardItem]) {
        pasteboard.clearContents()
        for item in items {
            let type = NSPasteboard.PasteboardType(item.type)
            pasteboard.setData(item.data, forType: type)
        }
    }
}

final class SystemKeyEventSender: KeyEventSenderProtocol {
    func sendCmdV() throws {
        // Key code 9 = 'V' key
        let keyCode: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            throw TalkKeyError.insertionFailed("Failed to create key down event")
        }
        guard let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw TalkKeyError.insertionFailed("Failed to create key up event")
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
