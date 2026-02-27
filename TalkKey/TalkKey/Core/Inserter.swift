import AppKit

protocol PasteboardProviderProtocol: AnyObject {
    func backup() -> [PasteboardItem]
    func setText(_ text: String)
    func restore(items: [PasteboardItem])
}

protocol KeyEventSenderProtocol: AnyObject {
    func sendCmdV() throws
}

final class Inserter: InserterProtocol {
    private let pasteboardProvider: PasteboardProviderProtocol
    private let keyEventSender: KeyEventSenderProtocol
    private let restoreDelay: TimeInterval
    private let logger: LoggerProtocol

    init(
        pasteboardProvider: PasteboardProviderProtocol = SystemPasteboardProvider(),
        keyEventSender: KeyEventSenderProtocol = SystemKeyEventSender(),
        restoreDelay: TimeInterval = 0.1,
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

        do {
            try keyEventSender.sendCmdV()
        } catch {
            logger.error("Cmd+V failed: \(error.localizedDescription)")
            throw error
        }

        if restoreDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(restoreDelay * 1_000_000_000))
        }

        pasteboardProvider.restore(items: backedUpItems)
        logger.debug("Text inserted, clipboard restored")
    }
}

// MARK: - System Implementations

final class SystemPasteboardProvider: PasteboardProviderProtocol {
    private let pasteboard = NSPasteboard.general

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
