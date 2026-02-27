import AppKit

final class LogViewerWindow {
    private let reader: LogFileReader
    private var window: NSWindow?
    private var textView: NSTextView?
    private var currentFilter: LogFilter = .all

    init(reader: LogFileReader) {
        self.reader = reader
    }

    func showWindow() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "TalkKey ログ"
        w.center()
        w.isReleasedWhenClosed = false

        let contentView = NSView(frame: w.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        w.contentView = contentView

        // Toolbar area
        let toolbar = NSView(frame: NSRect(x: 0, y: contentView.bounds.height - 40, width: contentView.bounds.width, height: 40))
        toolbar.autoresizingMask = [.width, .minYMargin]
        contentView.addSubview(toolbar)

        // Segmented control
        let segmented = NSSegmentedControl(labels: ["すべて", "LLM", "エラー"], trackingMode: .selectOne, target: nil, action: nil)
        segmented.selectedSegment = 0
        segmented.frame = NSRect(x: 12, y: 6, width: 240, height: 28)
        segmented.target = self
        segmented.action = #selector(filterChanged(_:))
        toolbar.addSubview(segmented)

        // Reload button
        let reloadButton = NSButton(title: "リロード", target: self, action: #selector(reload))
        reloadButton.bezelStyle = .rounded
        reloadButton.frame = NSRect(x: contentView.bounds.width - 100, y: 6, width: 88, height: 28)
        reloadButton.autoresizingMask = [.minXMargin]
        toolbar.addSubview(reloadButton)

        // Scroll view + text view
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: contentView.bounds.width, height: contentView.bounds.height - 40))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let tv = NSTextView(frame: scrollView.contentView.bounds)
        tv.autoresizingMask = [.width]
        tv.isEditable = false
        tv.isSelectable = true
        tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.backgroundColor = NSColor.textBackgroundColor
        tv.textContainerInset = NSSize(width: 8, height: 8)
        scrollView.documentView = tv
        contentView.addSubview(scrollView)

        self.window = w
        self.textView = tv

        reload()

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: currentFilter = .all
        case 1: currentFilter = .llmOnly
        case 2: currentFilter = .errorsOnly
        default: currentFilter = .all
        }
        reload()
    }

    @objc private func reload() {
        let entries = reader.readFiltered(filter: currentFilter)
        let text = entries.map { $0.rawLine }.joined(separator: "\n")
        textView?.string = text

        // Scroll to bottom
        if let tv = textView {
            tv.scrollRangeToVisible(NSRange(location: tv.string.count, length: 0))
        }
    }
}
