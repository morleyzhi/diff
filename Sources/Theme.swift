import AppKit

enum DiffTheme {
    static let deleteLine = NSColor(name: "diffDeleteLine") { appearance in
        if appearance.isDark {
            return NSColor(calibratedRed: 0.62, green: 0.20, blue: 0.22, alpha: 0.38)
        }
        return NSColor(calibratedRed: 1.00, green: 0.90, blue: 0.90, alpha: 1)
    }

    static let deleteChar = NSColor(name: "diffDeleteChar") { appearance in
        if appearance.isDark {
            return NSColor(calibratedRed: 0.78, green: 0.24, blue: 0.26, alpha: 0.78)
        }
        return NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.72, alpha: 1)
    }

    static let insertLine = NSColor(name: "diffInsertLine") { appearance in
        if appearance.isDark {
            return NSColor(calibratedRed: 0.18, green: 0.46, blue: 0.28, alpha: 0.40)
        }
        return NSColor(calibratedRed: 0.88, green: 0.97, blue: 0.90, alpha: 1)
    }

    static let insertChar = NSColor(name: "diffInsertChar") { appearance in
        if appearance.isDark {
            return NSColor(calibratedRed: 0.22, green: 0.62, blue: 0.36, alpha: 0.80)
        }
        return NSColor(calibratedRed: 0.62, green: 0.90, blue: 0.70, alpha: 1)
    }

    static let currentHunk = NSColor(name: "diffCurrentHunk") { appearance in
        if appearance.isDark {
            return NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.95, alpha: 0.22)
        }
        return NSColor(calibratedRed: 0.80, green: 0.88, blue: 1.00, alpha: 0.45)
    }

    static let minimapDelete = NSColor(name: "diffMinimapDelete") { appearance in
        if appearance.isDark {
            return NSColor(calibratedRed: 0.92, green: 0.40, blue: 0.42, alpha: 0.95)
        }
        return NSColor(calibratedRed: 0.86, green: 0.28, blue: 0.30, alpha: 0.95)
    }

    static let minimapInsert = NSColor(name: "diffMinimapInsert") { appearance in
        if appearance.isDark {
            return NSColor(calibratedRed: 0.40, green: 0.82, blue: 0.52, alpha: 0.95)
        }
        return NSColor(calibratedRed: 0.22, green: 0.64, blue: 0.36, alpha: 0.95)
    }

    static let placeholder = NSColor.tertiaryLabelColor
    static let lineNumber = NSColor.tertiaryLabelColor
    static let gutter = NSColor(name: "diffGutter") { appearance in
        if appearance.isDark {
            return NSColor(calibratedWhite: 1, alpha: 0.03)
        }
        return NSColor(calibratedWhite: 0, alpha: 0.03)
    }
}

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
