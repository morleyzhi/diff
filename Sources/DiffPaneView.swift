import AppKit

final class DiffPaneView: NSView {
    let side: Side
    unowned let model: AppModel

    private let header = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let pasteButton = NSButton(title: "Paste", target: nil, action: nil)
    private let scrollView = NSScrollView()
    private let textView = PaneTextView()
    private let placeholderLabel = NSTextField(labelWithString: "")

    private var isApplyingText = false
    private var isSyncingScroll = false
    private var isFocused = false
    private var flashWorkItem: DispatchWorkItem?

    init(side: Side, model: AppModel) {
        self.side = side
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 8
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
        let inset: CGFloat = 4
        let headerHeight: CGFloat = 34
        header.frame = NSRect(
            x: inset,
            y: bounds.height - inset - headerHeight,
            width: bounds.width - inset * 2,
            height: headerHeight
        )
        titleLabel.frame = NSRect(x: 10, y: 6, width: max(80, header.bounds.width - 100), height: 22)
        pasteButton.frame = NSRect(x: header.bounds.width - 78, y: 4, width: 68, height: 26)

        let body = NSRect(
            x: inset,
            y: inset,
            width: bounds.width - inset * 2,
            height: max(0, bounds.height - inset * 2 - headerHeight - 2)
        )
        scrollView.frame = body
        placeholderLabel.frame = body.insetBy(dx: 16, dy: 14)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        if view === placeholderLabel {
            return textView
        }
        return view
    }

    override func mouseDown(with event: NSEvent) {
        focusEditor()
        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, model.focusedSide == side {
            DispatchQueue.main.async { [weak self] in
                self?.focusEditor()
            }
        }
    }

    func focusEditor() {
        window?.makeFirstResponder(textView)
        setFocused(true)
    }

    func syncFromModel() {
        applyModelUpdates(forceText: true)
    }

    func applyModelUpdates(forceText: Bool = false) {
        let text = side == .left ? model.leftText : model.rightText
        let editingHere = window?.firstResponder === textView
        if forceText || !editingHere {
            setTextIfNeeded(text)
        }
        applyHighlights()
        updatePlaceholder()
        updateChrome()
        textView.font = model.font()
    }

    func setTextIfNeeded(_ text: String) {
        if textView.string == text { return }
        isApplyingText = true
        let selected = textView.selectedRange()
        textView.string = text
        let length = (text as NSString).length
        let location = min(selected.location, length)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        isApplyingText = false
        updatePlaceholder()
    }

    func replaceWithPasteboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        focusEditor()
        let previous = textView.string
        model.setText(text, side: side)
        setTextIfNeeded(side == .left ? model.leftText : model.rightText)
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))
        flashPasteFeedback(replaced: previous != textView.string)
        if side == .left, model.rightText.isEmpty {
            model.focusedSide = .right
            model.rightPane?.focusEditor()
        }
    }

    func applyHighlights() {
        guard let layoutManager = textView.layoutManager else { return }
        let storageLength = textView.textStorage?.length ?? 0
        let full = NSRange(location: 0, length: storageLength)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)

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
                if let range = Self.utf16Range(ofCharacters: change, inLineAt: start, line: lineText ?? "") {
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
        let changed = isFocused != focused
        isFocused = focused
        if focused {
            model.focusedSide = side
        }
        if changed {
            updateChrome()
        }
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

    func didPasteInEditor() {
        let selected = textView.selectedRange()
        textView.scrollRangeToVisible(selected)
        flashPasteFeedback(replaced: false)
        if side == .left, model.rightText.isEmpty, !textView.string.isEmpty {
            model.focusedSide = .right
            model.rightPane?.focusEditor()
        }
    }

    private func setup() {
        header.wantsLayer = true
        header.layer?.cornerRadius = 6
        addSubview(header)

        titleLabel.stringValue = side == .left ? "Original" : "Changed"
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        header.addSubview(titleLabel)

        pasteButton.bezelStyle = .rounded
        pasteButton.controlSize = .small
        pasteButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        pasteButton.target = self
        pasteButton.action = #selector(pasteButtonClicked)
        pasteButton.toolTip = side == .left ? "Replace left side with clipboard (⌘⇧1)" : "Replace right side with clipboard (⌘⇧2)"
        header.addSubview(pasteButton)

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
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 8
        textView.textContainerInset = NSSize(width: 8, height: 10)

        scrollView.documentView = textView
        addSubview(scrollView)

        placeholderLabel.stringValue = side == .left
            ? "Click here, then paste (⌘V)\nor use the Paste button"
            : "Click here, then paste (⌘V)\nor use the Paste button"
        placeholderLabel.textColor = DiffTheme.placeholder
        placeholderLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        placeholderLabel.alignment = .left
        placeholderLabel.lineBreakMode = .byWordWrapping
        placeholderLabel.maximumNumberOfLines = 4
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

    @objc private func pasteButtonClicked() {
        replaceWithPasteboard()
    }

    private func updateChrome() {
        let accent = NSColor.controlAccentColor
        layer?.borderWidth = isFocused ? 3 : 1
        layer?.borderColor = (isFocused ? accent : NSColor.separatorColor).cgColor

        let bodyBackground: NSColor
        let headerBackground: NSColor
        if isFocused {
            bodyBackground = NSColor.textBackgroundColor.blended(withFraction: 0.16, of: accent)
                ?? NSColor.textBackgroundColor
            headerBackground = accent.withAlphaComponent(0.18)
            titleLabel.textColor = .labelColor
        } else {
            bodyBackground = .textBackgroundColor
            headerBackground = NSColor.controlBackgroundColor.withAlphaComponent(0.65)
            titleLabel.textColor = .secondaryLabelColor
        }

        textView.backgroundColor = bodyBackground
        scrollView.backgroundColor = bodyBackground
        layer?.backgroundColor = bodyBackground.cgColor
        header.layer?.backgroundColor = headerBackground.cgColor
        pasteButton.contentTintColor = isFocused ? accent : .secondaryLabelColor
    }

    private func updatePlaceholder() {
        placeholderLabel.isHidden = !textView.string.isEmpty
    }

    private func flashPasteFeedback(replaced: Bool) {
        flashWorkItem?.cancel()
        wantsLayer = true
        let flash = CABasicAnimation(keyPath: "backgroundColor")
        flash.fromValue = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
        flash.toValue = textView.backgroundColor.cgColor
        flash.duration = 0.45
        layer?.add(flash, forKey: "pasteFlash")

        titleLabel.stringValue = replaced
            ? (side == .left ? "Original · pasted" : "Changed · pasted")
            : (side == .left ? "Original · updated" : "Changed · updated")

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.titleLabel.stringValue = self.side == .left ? "Original" : "Changed"
        }
        flashWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    @objc private func scrollViewDidScroll(_ notification: Notification) {
        if isSyncingScroll { return }
        model.paneDidScroll(side: side, progress: currentScrollProgress())
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let url = urls.first {
            model.loadFile(url, into: side)
            focusEditor()
            flashPasteFeedback(replaced: true)
            return true
        }
        if let text = pasteboard.string(forType: .string) {
            model.setText(text, side: side)
            focusEditor()
            flashPasteFeedback(replaced: true)
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
        return starts
    }

    private static func utf16Range(
        ofCharacters range: Range<Int>,
        inLineAt lineStart: Int,
        line: String
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
        // Replace-all when empty or everything is selected; otherwise insert like a textarea.
        let allSelected = selectedRange().length == (string as NSString).length && !string.isEmpty
        if string.isEmpty || allSelected {
            pane?.replaceWithPasteboard()
            return
        }
        super.paste(sender)
        pane?.handleTextChange()
        pane?.didPasteInEditor()
    }

    override func mouseDown(with event: NSEvent) {
        pane?.setFocused(true)
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
