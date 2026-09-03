import AppKit

final class DiffPaneView: NSView {
    let side: Side
    unowned let model: AppModel
    private var selectionAnchor: TextPosition?
    private var selectionEnd: TextPosition?

    init(side: Side, model: AppModel) {
        self.side = side
        self.model = model
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, model.focusedSide == side {
            window?.makeFirstResponder(self)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .iBeam)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        let rows = model.rows
        let font = model.font()
        let lineHeight = model.lineHeight
        let charWidth = max(font.maximumAdvancement.width, 7)
        let first = max(0, Int(model.scrollOffset.rounded(.down)))
        let last = min(rows.count, first + Int(bounds.height / lineHeight) + 2)
        let gutter = gutterWidth(charWidth: charWidth, rows: rows)
        let horizontal = side == .left ? model.leftHorizontal : model.rightHorizontal
        let currentHunk = model.hunks.indices.contains(model.currentHunkIndex) ? model.hunks[model.currentHunkIndex] : nil
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: DiffTheme.lineNumber,
        ]

        DiffTheme.gutter.setFill()
        CGRect(x: 0, y: 0, width: gutter, height: bounds.height).fill()

        if rows.isEmpty {
            drawPlaceholder(gutter: gutter)
            return
        }

        for index in first..<last {
            let row = rows[index]
            let y = (CGFloat(index) - model.scrollOffset) * lineHeight
            let rowRect = CGRect(x: 0, y: y, width: bounds.width, height: lineHeight)
            if let currentHunk, currentHunk.rows.contains(index) {
                DiffTheme.currentHunk.setFill()
                rowRect.fill()
            }
            drawRowBackground(row, in: rowRect, gutter: gutter)
            drawLineNumber(row, y: y, gutter: gutter, attributes: numberAttributes)
            drawRowText(row, y: y, gutter: gutter, charWidth: charWidth, horizontal: horizontal, attributes: textAttributes)
        }

        if let selection = normalizedSelection() {
            drawSelection(selection, first: first, last: last, gutter: gutter, charWidth: charWidth, lineHeight: lineHeight, horizontal: horizontal)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        model.focusedSide = side
        let position = position(at: convert(event.locationInWindow, from: nil))
        if event.clickCount >= 3 {
            selectionAnchor = TextPosition(row: position.row, column: 0)
            selectionEnd = TextPosition(row: position.row, column: lineLength(position.row))
        } else if event.clickCount == 2 {
            selectionAnchor = wordBoundary(from: position, forward: false)
            selectionEnd = wordBoundary(from: position, forward: true)
        } else {
            selectionAnchor = position
            selectionEnd = position
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        selectionEnd = position(at: convert(event.locationInWindow, from: nil))
        if let end = selectionEnd {
            reveal(end.row)
        }
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            let current = side == .left ? model.leftHorizontal : model.rightHorizontal
            model.setHorizontal(current - event.scrollingDeltaX, side: side)
            return
        }
        model.scroll(by: event.scrollingDeltaY)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125:
            model.scroll(by: -model.lineHeight * (event.modifierFlags.contains(.command) ? 0 : 1))
            if event.modifierFlags.contains(.command) { model.nextHunk() }
        case 126:
            model.scroll(by: model.lineHeight * (event.modifierFlags.contains(.command) ? 0 : 1))
            if event.modifierFlags.contains(.command) { model.prevHunk() }
        case 121:
            model.scroll(by: -bounds.height)
        case 116:
            model.scroll(by: bounds.height)
        case 119:
            model.setScroll(model.maxScrollOffset)
        case 115:
            model.setScroll(0)
        default:
            interpretKeyEvents([event])
        }
    }

    override func selectAll(_ sender: Any?) {
        if model.rows.isEmpty { return }
        selectionAnchor = TextPosition(row: 0, column: 0)
        let last = model.rows.count - 1
        selectionEnd = TextPosition(row: last, column: lineLength(last))
        needsDisplay = true
    }

    @objc func paste(_ sender: Any?) {
        model.paste(into: side)
    }

    @objc func copy(_ sender: Any?) {
        model.copySelection(from: side)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
            paste(nil)
            return true
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
            copy(nil)
            return true
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "a" {
            selectAll(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], let url = urls.first {
            model.loadFile(url, into: side)
            return true
        }
        if let text = pasteboard.string(forType: .string) {
            model.setText(text, side: side)
            return true
        }
        return false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Paste", action: #selector(paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Clear", action: #selector(clearSide), keyEquivalent: "")
        menu.addItem(withTitle: "Open File…", action: #selector(openSide), keyEquivalent: "o")
        return menu
    }

    @objc private func clearSide() {
        model.clear(side: side)
    }

    @objc private func openSide() {
        model.openFile(into: side)
    }

    func selectedText() -> String {
        guard let selection = normalizedSelection() else {
            return side == .left ? model.leftText : model.rightText
        }
        var lines: [String] = []
        for row in selection.start.row...selection.end.row {
            let text = lineText(row)
            let start = row == selection.start.row ? min(selection.start.column, text.count) : 0
            let end = row == selection.end.row ? min(selection.end.column, text.count) : text.count
            if start <= end {
                let startIndex = text.index(text.startIndex, offsetBy: start)
                let endIndex = text.index(text.startIndex, offsetBy: end)
                lines.append(String(text[startIndex..<endIndex]))
            }
        }
        return lines.joined(separator: "\n")
    }

    func visibleTextWidth() -> CGFloat {
        max(0, bounds.width - gutterWidth(charWidth: model.monospacedAdvance(), rows: model.rows) - 8)
    }

    private func drawPlaceholder(gutter: CGFloat) {
        let text = side == .left ? "Paste original text (⌘V)" : "Paste changed text (⌘V)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: DiffTheme.placeholder,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let point = CGPoint(
            x: gutter + max(16, (bounds.width - gutter - size.width) / 2),
            y: max(16, (bounds.height - size.height) / 2)
        )
        (text as NSString).draw(at: point, withAttributes: attributes)
    }

    private func drawRowBackground(_ row: DiffRow, in rect: CGRect, gutter: CGFloat) {
        let textRect = CGRect(x: gutter, y: rect.minY, width: rect.width - gutter, height: rect.height)
        switch (side, row.kind) {
        case (.left, .delete), (.left, .replace):
            DiffTheme.deleteLine.setFill()
            textRect.fill()
        case (.right, .insert), (.right, .replace):
            DiffTheme.insertLine.setFill()
            textRect.fill()
        default:
            break
        }

        let marker = CGRect(x: gutter - 3, y: rect.minY, width: 3, height: rect.height)
        switch (side, row.kind) {
        case (.left, .delete), (.left, .replace):
            DiffTheme.minimapDelete.setFill()
            marker.fill()
        case (.right, .insert), (.right, .replace):
            DiffTheme.minimapInsert.setFill()
            marker.fill()
        default:
            break
        }
    }

    private func drawLineNumber(_ row: DiffRow, y: CGFloat, gutter: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let number = side == .left ? row.leftNumber : row.rightNumber
        guard let number else { return }
        let text = "\(number)" as NSString
        let size = text.size(withAttributes: attributes)
        let point = CGPoint(x: gutter - size.width - 10, y: y + 1)
        text.draw(at: point, withAttributes: attributes)
    }

    private func drawRowText(
        _ row: DiffRow,
        y: CGFloat,
        gutter: CGFloat,
        charWidth: CGFloat,
        horizontal: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        guard let text = side == .left ? row.left : row.right else { return }
        let changes = side == .left ? row.leftChanges : row.rightChanges
        let charColor = side == .left ? DiffTheme.deleteChar : DiffTheme.insertChar
        let textX = gutter + 8 - horizontal * charWidth

        charColor.setFill()
        for range in changes {
            let rect = CGRect(
                x: textX + CGFloat(range.lowerBound) * charWidth,
                y: y,
                width: CGFloat(max(1, range.count)) * charWidth,
                height: model.lineHeight
            )
            rect.fill()
        }

        (text as NSString).draw(
            with: CGRect(x: textX, y: y, width: 100_000, height: model.lineHeight),
            options: [.usesLineFragmentOrigin],
            attributes: attributes
        )
    }

    private func drawSelection(
        _ selection: (start: TextPosition, end: TextPosition),
        first: Int,
        last: Int,
        gutter: CGFloat,
        charWidth: CGFloat,
        lineHeight: CGFloat,
        horizontal: CGFloat
    ) {
        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35).setFill()
        let startRow = max(first, selection.start.row)
        let endRow = min(last - 1, selection.end.row)
        if startRow > endRow { return }
        for row in startRow...endRow {
            let startCol = row == selection.start.row ? selection.start.column : 0
            let endCol = row == selection.end.row ? selection.end.column : max(lineLength(row), 1)
            let x = gutter + 8 + (CGFloat(startCol) - horizontal) * charWidth
            let width = CGFloat(max(1, endCol - startCol)) * charWidth
            let y = (CGFloat(row) - model.scrollOffset) * lineHeight
            CGRect(x: x, y: y, width: width, height: lineHeight).fill()
        }
    }

    private func gutterWidth(charWidth: CGFloat, rows: [DiffRow]) -> CGFloat {
        let digits = max(3, String(max(rows.count, 1)).count)
        return CGFloat(digits) * charWidth + 20
    }

    private func position(at point: CGPoint) -> TextPosition {
        let charWidth = max(model.monospacedAdvance(), 7)
        let gutter = gutterWidth(charWidth: charWidth, rows: model.rows)
        let row = min(max(0, Int(((point.y / model.lineHeight) + model.scrollOffset).rounded(.down))), max(0, model.rows.count - 1))
        let column = max(0, Int(((point.x - gutter - 8) / charWidth + (side == .left ? model.leftHorizontal : model.rightHorizontal)).rounded(.down)))
        return TextPosition(row: row, column: min(column, lineLength(row)))
    }

    private func lineText(_ row: Int) -> String {
        guard model.rows.indices.contains(row) else { return "" }
        return (side == .left ? model.rows[row].left : model.rows[row].right) ?? ""
    }

    private func lineLength(_ row: Int) -> Int {
        lineText(row).count
    }

    private func reveal(_ row: Int) {
        let first = model.scrollOffset
        let last = first + model.visibleLineCount() - 1
        if CGFloat(row) < first {
            model.setScroll(CGFloat(row))
        } else if CGFloat(row) > last {
            model.setScroll(CGFloat(row) - model.visibleLineCount() + 1)
        }
    }

    private func wordBoundary(from position: TextPosition, forward: Bool) -> TextPosition {
        let text = Array(lineText(position.row))
        if text.isEmpty { return position }
        var column = min(max(position.column, 0), text.count)
        if forward {
            while column < text.count, text[column].isWhitespace { column += 1 }
            while column < text.count, !text[column].isWhitespace { column += 1 }
        } else {
            while column > 0, text[column - 1].isWhitespace { column -= 1 }
            while column > 0, !text[column - 1].isWhitespace { column -= 1 }
        }
        return TextPosition(row: position.row, column: column)
    }

    private func normalizedSelection() -> (start: TextPosition, end: TextPosition)? {
        guard let start = selectionAnchor, let end = selectionEnd else { return nil }
        if start.row > end.row || (start.row == end.row && start.column > end.column) {
            return (end, start)
        }
        if start.row == end.row && start.column == end.column { return nil }
        return (start, end)
    }
}

private struct TextPosition {
    var row: Int
    var column: Int
}
