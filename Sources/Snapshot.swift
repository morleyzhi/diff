import AppKit

enum Snapshot {
    @MainActor
    static func render(model: AppModel, size: CGSize, to url: URL) throws {
        model.restoreIfNeeded()
        let deadline = Date().addingTimeInterval(2)
        while model.isComputing && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        if model.isActive && model.rows.isEmpty {
            model.scheduleRecompute()
            while model.isComputing && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
        }

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let paneWidth = (size.width - 36) / 2
        let left = DiffPaneView(side: .left, model: model)
        left.frame = NSRect(x: 0, y: 0, width: paneWidth, height: size.height)
        let minimap = MinimapView(model: model)
        minimap.frame = NSRect(x: paneWidth, y: 0, width: 36, height: size.height)
        let right = DiffPaneView(side: .right, model: model)
        right.frame = NSRect(x: paneWidth + 36, y: 0, width: paneWidth, height: size.height)

        model.leftPane = left
        model.rightPane = right
        model.minimap = minimap

        root.addSubview(left)
        root.addSubview(minimap)
        root.addSubview(right)

        left.syncFromModel()
        right.syncFromModel()
        left.layoutSubtreeIfNeeded()
        right.layoutSubtreeIfNeeded()
        minimap.layoutSubtreeIfNeeded()
        left.display()
        right.display()
        minimap.display()

        let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds)!
        root.cacheDisplay(in: root.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "DiffSnapshot", code: 1)
        }
        try png.write(to: url)
    }
}
