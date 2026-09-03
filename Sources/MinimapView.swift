import AppKit

final class MinimapView: NSView {
    unowned let model: AppModel
    private var isDragging = false

    init(model: AppModel) {
        self.model = model
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        NSColor.separatorColor.setStroke()
        let leftBorder = NSBezierPath()
        leftBorder.move(to: NSPoint(x: 0.5, y: 0))
        leftBorder.line(to: NSPoint(x: 0.5, y: bounds.height))
        leftBorder.lineWidth = 1
        leftBorder.stroke()
        let rightBorder = NSBezierPath()
        rightBorder.move(to: NSPoint(x: bounds.width - 0.5, y: 0))
        rightBorder.line(to: NSPoint(x: bounds.width - 0.5, y: bounds.height))
        rightBorder.lineWidth = 1
        rightBorder.stroke()

        let rows = model.rows
        let hunks = model.hunks
        guard !rows.isEmpty else { return }

        let padding: CGFloat = 4
        let columnWidth = (bounds.width - padding * 2 - 4) / 2
        let leftX = padding
        let rightX = padding + columnWidth + 4
        let track = bounds.insetBy(dx: 0, dy: 6)
        let scale = track.height / CGFloat(rows.count)

        NSColor.tertiaryLabelColor.withAlphaComponent(0.12).setFill()
        CGRect(x: leftX, y: track.minY, width: columnWidth, height: track.height).fill()
        CGRect(x: rightX, y: track.minY, width: columnWidth, height: track.height).fill()

        for hunk in hunks {
            let y = track.minY + CGFloat(hunk.rows.lowerBound) * scale
            let height = max(2, CGFloat(hunk.rows.count) * scale)
            if hunk.hasDelete {
                DiffTheme.minimapDelete.setFill()
                CGRect(x: leftX, y: y, width: columnWidth, height: height).fill()
            }
            if hunk.hasInsert {
                DiffTheme.minimapInsert.setFill()
                CGRect(x: rightX, y: y, width: columnWidth, height: height).fill()
            }
        }

        if model.hunks.indices.contains(model.currentHunkIndex) {
            let hunk = model.hunks[model.currentHunkIndex]
            let y = track.minY + CGFloat(hunk.rows.lowerBound) * scale
            let height = max(2, CGFloat(hunk.rows.count) * scale)
            NSColor.controlAccentColor.withAlphaComponent(0.28).setFill()
            CGRect(x: 1, y: y, width: bounds.width - 2, height: height).fill()
        }

        let visible = model.visibleLineCount()
        let viewportHeight = max(8, min(track.height, visible * scale))
        let maxOffset = max(1, model.maxScrollOffset)
        let progress = model.maxScrollOffset == 0 ? 0 : model.scrollOffset / maxOffset
        let viewportY = track.minY + progress * (track.height - viewportHeight)
        let viewport = CGRect(x: 2, y: viewportY, width: bounds.width - 4, height: viewportHeight)
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        viewport.fill()
        NSColor.labelColor.withAlphaComponent(0.35).setStroke()
        let path = NSBezierPath(rect: viewport.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        jump(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        jump(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }

    override func scrollWheel(with event: NSEvent) {
        model.scroll(by: event.scrollingDeltaY)
    }

    private func jump(to point: CGPoint) {
        let rows = model.rows
        if rows.isEmpty { return }
        let track = bounds.insetBy(dx: 0, dy: 6)
        let clampedY = min(max(point.y, track.minY), track.maxY)
        let progress = (clampedY - track.minY) / max(track.height, 1)
        let target = progress * CGFloat(rows.count) - model.visibleLineCount() / 2
        model.setScroll(target)
    }
}
