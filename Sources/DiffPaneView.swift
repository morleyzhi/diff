import AppKit

final class DiffPaneView: NSView {
    let side: Side
    unowned let model: AppModel

    private let scrollView = NSScrollView()
    private let textView = PaneTextView()
    private var isApplyingText = false
    private var isSyncingScroll = false
    private var isFocused = false
    private var placeholderLabel = NSTextField(labelWithString: "")

    init(side: Side, model: AppModel) {
        self.side = side
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 6
        setup()
        syncFromModel()
        updateChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { true }

    override func layout() {
        super.layout()
        let inset: CGFloat = 3
        scrollView.frame = bounds.insetBy(dx: inset, dy: inset)
        placeholderLabel.frame = scrollView.frame.insetBy(dx: 18, dy: 18)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        if view === placeholderLabel {
            return textView
        }
        return view
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, model.focusedSide == side {
            focusEditor()
        }
    }

    func focusEditor() {
        window?.makeFirstResponder(textView)
    }

    func syncFromModel() {
        let text = side == .left ? model.leftText : model.rightText
        setTextIfNeeded(text)
        applyHighlights()
        updatePlaceholder()
        updateChrome()
    }

    func setTextIfNeeded(_ text: String) {
        if textView.string == text { return }
        isApplyingText = true
        let selected = textView.selectedRange()
        textView.string = text
        let clamped = NSRange(location: min(selected.location, (text as NSString).length), length: 0)
        textView.setSelectedRange(clamped)
        isApplyingText = false
        updatePlaceholder()
    }

    func applyHighlights() {
        guard let layoutManager = textView.layoutManager else { return }
        let storage = textView.textStorage
        let full = NSRange(location: 0, length: storage?.length ?? 0)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: full)

        guard model.isActive else { return }

        let text = textView.string
        let lineStarts = Self.lineStartOffsets(in: text)
        let lineColor = side == .left ? DiffTheme.deleteLine : DiffTheme.insertLine
        let charColor = side == .left ? DiffTheme.deleteChar : DiffTheme.insertChar

        for row in model.rows {
            let lineNumber = side == .left ? row.leftNumber : row.rightNumber
            let lineText = side == .left ? row.left : row.right
            let changes = side == .left ? row.leftChanges : row.rightChanges
            let shouldHighlight: Bool = {
                switch (side, row.kind) {
                case (.left, .delete), (.left, .replace), (.right, .insert), (.right, .replace):
                    return true
                default:
                    return false
                }
            }()

            guard shouldHighlight, let lineNumber, lineText != nil else { continue }
            let index = lineNumber - 1
            guard lineStarts.indices.contains(index) else { continue }
            let start = lineStarts[index]
            let lineRange = (text as NSString).lineRange(for: NSRange(location: start, length: 0))
            layoutManager.addTemporaryAttribute(.backgroundColor, value: lineColor, forCharacterRange: lineRange)

            for change in changes {
                if let range = Self.utf16Range(ofCharacters: change, inLineAt: start, line: lineText ?? "", fullText: text) {
                    layoutManager.addTemporaryAttribute(.backgroundColor, value: charColor, forCharacterRange: range)
                }
            }
        }
    }

    func scrollToLine(_ line: Int) {
        let text = textView.string as NSString
        guard line > 0 else { return }
        let starts = Self.lineStartOffsets(in: text as String)
        let index = min(line - 1, max(0, starts.count - 1))
        guard starts.indices.contains(index) else { return }
        let range = NSRange(location: starts[index], length: 0)
        isSyncingScroll = true
        textView.scrollRangeToVisible(range)
        isSyncingScroll = false
    }

    func scrollToProgress(_ progress: CGFloat) {
        guard let doc = scrollView.documentView else { return }
        let clip = scrollView.contentView.bounds
        let maxY = max(0, doc.bounds.height - clip.height)
        var origin = clip.origin
        origin.y = min(max(0, progress), 1) * maxY
        isSyncingScroll = true
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isSyncingScroll = false
    }

    func currentScrollProgress() -> CGFloat {
        guard let doc = scrollView.documentView else { return 0 }
        let clip = scrollView.contentView.bounds
        let maxY = max(0, doc.bounds.height - clip.height)
        if maxY <= 0 { return 0 }
        return min(max(0, clip.minY / maxY), 1)
    }

    func selectedText() -> String {
        let range = textView.selectedRange()
        if range.length == 0 { return textView.string }
        return (textView.string as NSString).substring(with: range)
    }

    func visibleTextWidth() -> CGFloat {
        max(0, textView.bounds.width - 24)
    }

    func setFocused(_ focused: Bool) {
        isFocused = focused
        if focused {
            model.focusedSide = side
        }
        updateChrome()
    }

    private func setup() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        textView.pane = self
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = model.font()
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .labelColor
        textView.delegate = textView
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 8
        textView.textContainerInset = NSSize(width: 8, height: 10)

        scrollView.documentView = textView
        addSubview(scrollView)

        placeholderLabel.stringValue = side == .left ? "Paste original text (⌘V)" : "Paste changed text (⌘V)"
        placeholderLabel.textColor = DiffTheme.placeholder
        placeholderLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        placeholderLabel.alignment = .left
        placeholderLabel.lineBreakMode = .byWordWrapping
        placeholderLabel.maximumNumberOfLines = 3
        addSubview(placeholderLabel)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        registerForDraggedTypes([.fileURL, .string])
    }

    private func updateChrome() {
        layer?.borderWidth = isFocused ? 2 : 1
        layer?.borderColor = (isFocused ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        let background: NSColor
        if isFocused {
            background = NSColor.textBackgroundColor.blended(withFraction: 0.08, of: .controlAccentColor)
                ?? NSColor.textBackgroundColor
        } else {
            background = .textBackgroundColor
        }
        textView.backgroundColor = background
        scrollView.backgroundColor = background
        layer?.backgroundColor = background.cgColor
    }

    private func updatePlaceholder() {
        placeholderLabel.isHidden = !textView.string.isEmpty
    }

    @objc private func scrollViewDidScroll(_ notification: Notification) {
        if isSyncingScroll { return }
        model.paneDidScroll(side: side, progress: currentScrollProgress())
    }

    func handleTextChange() {
        if isApplyingText { return }
        updatePlaceholder()
        model.setText(textView.string, side: side)
    }

    func handleFontChange() {
        textView.font = model.font()
        applyHighlights()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first {
            model.loadFile(url, into: side)
            focusEditor()
            return true
        }
        if let text = pasteboard.string(forType: .string) {
            model.setText(text, side: side)
            focusEditor()
            return true
        }
        return false
    }

    private static func lineStartOffsets(in text: String) -> [Int] {
        if text.isEmpty { return [0] }
        let ns = text as NSString
        var starts: [Int] = []
        var location = 0
        while location <= ns.length {
            starts.append(location)
            if location == ns.length { break }
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            let next = NSMaxRange(lineRange)
            if next <= location { break }
            location = next
        }
        if text.hasSuffix("\n") {
            // keep trailing empty line start already added when location == length
        }
        return starts
    }

    private static func utf16Range(
        ofCharacters range: Range<Int>,
        inLineAt lineStart: Int,
        line: String,
        fullText: String
    ) -> NSRange? {
        guard range.lowerBound >= 0, range.upperBound <= line.count else { return nil }
        let startIdx = line.index(line.startIndex, offsetBy: range.lowerBound)
        let endIdx = line.index(line.startIndex, offsetBy: range.upperBound)
        let relative = NSRange(startIdx..<endIdx, in: line)
        return NSRange(location: lineStart + relative.location, length: relative.length)
    }
}

final class PaneTextView: NSTextView, NSTextViewDelegate {
    weak var pane: DiffPaneView?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            pane?.setFocused(true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            pane?.setFocused(false)
        }
        return resigned
    }

    func textDidChange(_ notification: Notification) {
        pane?.handleTextChange()
    }

    override func paste(_ sender: Any?) {
        let wasEmpty = string.isEmpty
        let side = pane?.side
        super.paste(sender)
        pane?.handleTextChange()
        if wasEmpty, side == .left, AppModel.shared.rightText.isEmpty {
            AppModel.shared.focusedSide = .right
            AppModel.shared.rightPane?.focusEditor()
        }
    }

    override func mouseDown(with event: NSEvent) {
        pane?.setFocused(true)
        super.mouseDown(with: event)
    }
}
