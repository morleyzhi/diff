import AppKit
import Foundation
import Observation

enum Side: String, Sendable {
    case left
    case right
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var leftText = ""
    var rightText = ""
    var ignoreWhitespace = true {
        didSet {
            if !restoring, oldValue != ignoreWhitespace {
                persistState()
                scheduleRecompute()
            }
        }
    }
    var fontSize: CGFloat = 12.5
    var focusedSide: Side = .left
    var isComputing = false
    var currentHunkIndex = 0
    var statusText = "Paste text on both sides"

    private(set) var result = DiffResult(rows: [], hunks: [], maxLeftChars: 0, maxRightChars: 0, identical: true)
    @ObservationIgnored var scrollOffset: CGFloat = 0
    @ObservationIgnored var leftHorizontal: CGFloat = 0
    @ObservationIgnored var rightHorizontal: CGFloat = 0

    @ObservationIgnored weak var leftPane: DiffPaneView?
    @ObservationIgnored weak var rightPane: DiffPaneView?
    @ObservationIgnored weak var minimap: MinimapView?

    @ObservationIgnored private var computeGeneration = 0
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    @ObservationIgnored private var restoring = false

    var rows: [DiffRow] { result.rows }
    var hunks: [DiffHunk] { result.hunks }
    var isActive: Bool { !leftText.isEmpty && !rightText.isEmpty }
    var hasDiff: Bool { isActive && !result.hunks.isEmpty }

    var hunkLabel: String {
        if !isActive { return "Paste both sides to diff" }
        if isComputing { return "Computing…" }
        if result.hunks.isEmpty { return "No differences" }
        return "\(currentHunkIndex + 1) of \(result.hunks.count)"
    }

    var lineHeight: CGFloat { max(16, (fontSize * 1.45).rounded()) }

    var maxScrollOffset: CGFloat {
        let visible = visibleLineCount()
        return max(0, CGFloat(rows.count) - visible)
    }

    func restoreIfNeeded() {
        if restoring { return }
        restoring = true
        defer { restoring = false }
        parseLaunchArguments()
        loadPersistedSession()
        scheduleRecompute()
    }

    func setText(_ text: String, side: Side) {
        switch side {
        case .left:
            leftText = text
        case .right:
            rightText = text
        }
        if side == .left, rightText.isEmpty {
            focusedSide = .right
            rightPane?.window?.makeFirstResponder(rightPane)
        } else {
            focusedSide = side
        }
        persistSessionSoon()
        scheduleRecompute()
    }

    func paste(into side: Side) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        focusedSide = side
        setText(text, side: side)
    }

    func pasteIntoFocused() {
        paste(into: focusedSide)
    }

    func clear(side: Side) {
        setText("", side: side)
    }

    func openFile(into side: Side) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = side == .left ? "Open left text" : "Open right text"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFile(url, into: side)
    }

    func loadFile(_ url: URL, into side: Side) {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            statusText = "Could not read \(url.lastPathComponent)"
            return
        }
        focusedSide = side
        setText(text, side: side)
    }

    func copySelection(from side: Side) {
        let pane = side == .left ? leftPane : rightPane
        let text = pane?.selectedText() ?? (side == .left ? leftText : rightText)
        if text.isEmpty { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func scheduleRecompute() {
        computeGeneration += 1
        let generation = computeGeneration
        let left = leftText
        let right = rightText
        let ignore = ignoreWhitespace

        if left.isEmpty && right.isEmpty {
            result = DiffResult(rows: [], hunks: [], maxLeftChars: 0, maxRightChars: 0, identical: true)
            currentHunkIndex = 0
            scrollOffset = 0
            isComputing = false
            statusText = "Paste text on both sides"
            refreshViews()
            return
        }

        if left.isEmpty || right.isEmpty {
            let filled = left.isEmpty ? right : left
            let side: Side = left.isEmpty ? .right : .left
            let preview = previewRows(text: filled, side: side)
            result = DiffResult(rows: preview.rows, hunks: [], maxLeftChars: preview.maxLeft, maxRightChars: preview.maxRight, identical: false)
            currentHunkIndex = 0
            isComputing = false
            statusText = side == .left ? "Paste the right side to diff" : "Paste the left side to diff"
            clampScroll()
            refreshViews()
            return
        }

        isComputing = true
        statusText = "Computing…"
        Task.detached(priority: .userInitiated) {
            let computed = DiffEngine.diff(left: left, right: right, ignoreWhitespace: ignore)
            await MainActor.run {
                guard generation == self.computeGeneration else { return }
                self.result = computed
                self.isComputing = false
                self.currentHunkIndex = 0
                self.statusText = computed.hunks.isEmpty ? "No differences" : "\(computed.hunks.count) changes"
                self.clampScroll()
                self.refreshViews()
            }
        }
    }

    func scroll(by deltaY: CGFloat) {
        setScroll(scrollOffset - deltaY / lineHeight)
    }

    func setScroll(_ value: CGFloat) {
        let clamped = min(max(0, value), maxScrollOffset)
        if clamped == scrollOffset { return }
        scrollOffset = clamped
        updateHunkFromScroll()
        refreshViews()
    }

    func setHorizontal(_ value: CGFloat, side: Side) {
        let maxChars = side == .left ? result.maxLeftChars : result.maxRightChars
        let pane = side == .left ? leftPane : rightPane
        let visibleChars = max(1, Int(((pane?.visibleTextWidth() ?? 400) / monospacedAdvance()) ))
        let maxOffset = max(0, CGFloat(maxChars - visibleChars + 4))
        let clamped = min(max(0, value), maxOffset)
        if side == .left {
            if leftHorizontal == clamped { return }
            leftHorizontal = clamped
            leftPane?.needsDisplay = true
        } else {
            if rightHorizontal == clamped { return }
            rightHorizontal = clamped
            rightPane?.needsDisplay = true
        }
    }

    func nextHunk() {
        if hunks.isEmpty { return }
        currentHunkIndex = (currentHunkIndex + 1) % hunks.count
        jumpToCurrentHunk()
    }

    func prevHunk() {
        if hunks.isEmpty { return }
        currentHunkIndex = (currentHunkIndex - 1 + hunks.count) % hunks.count
        jumpToCurrentHunk()
    }

    func jumpToCurrentHunk() {
        guard hunks.indices.contains(currentHunkIndex) else { return }
        let start = hunks[currentHunkIndex].rows.lowerBound
        setScroll(CGFloat(start) - 2)
        refreshViews()
    }

    func adjustFont(by delta: CGFloat) {
        fontSize = min(22, max(9, fontSize + delta))
        persistState()
        refreshViews()
    }

    func visibleLineCount() -> CGFloat {
        let height = leftPane?.bounds.height ?? rightPane?.bounds.height ?? 640
        return max(1, height / lineHeight)
    }

    func monospacedAdvance() -> CGFloat {
        font().maximumAdvancement.width
    }

    func font() -> NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    func refreshViews() {
        leftPane?.needsDisplay = true
        rightPane?.needsDisplay = true
        minimap?.needsDisplay = true
    }

    func saveNow() {
        persistTask?.cancel()
        writeSession()
    }

    private func jumpToRow(_ row: Int) {
        setScroll(CGFloat(row) - 2)
    }

    private func updateHunkFromScroll() {
        if hunks.isEmpty { return }
        let center = Int(scrollOffset + visibleLineCount() / 2)
        var best = 0
        var bestDistance = Int.max
        for (index, hunk) in hunks.enumerated() {
            let distance: Int
            if hunk.rows.contains(center) {
                currentHunkIndex = index
                return
            }
            distance = min(abs(hunk.rows.lowerBound - center), abs(hunk.rows.upperBound - 1 - center))
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        currentHunkIndex = best
    }

    private func clampScroll() {
        scrollOffset = min(max(0, scrollOffset), maxScrollOffset)
    }

    private func previewRows(text: String, side: Side) -> (rows: [DiffRow], maxLeft: Int, maxRight: Int) {
        let lines = DiffEngine.splitLines(text).map(DiffEngine.expandTabs)
        var maxChars = 0
        let rows: [DiffRow] = lines.enumerated().map { index, line in
            maxChars = max(maxChars, line.count)
            return DiffRow(
                kind: .equal,
                left: side == .left ? line : nil,
                right: side == .right ? line : nil,
                leftChanges: [],
                rightChanges: [],
                leftNumber: side == .left ? index + 1 : nil,
                rightNumber: side == .right ? index + 1 : nil
            )
        }
        return (rows, side == .left ? maxChars : 0, side == .right ? maxChars : 0)
    }

    private func parseLaunchArguments() {
        let arguments = CommandLine.arguments
        if arguments.contains("--self-test") { return }
        func value(for flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if let left = value(for: "--left") {
            leftText = (try? String(contentsOfFile: left, encoding: .utf8)) ?? leftText
        }
        if let right = value(for: "--right") {
            rightText = (try? String(contentsOfFile: right, encoding: .utf8)) ?? rightText
        }
        if let ignore = value(for: "--ignore-whitespace") {
            ignoreWhitespace = ignore != "false" && ignore != "0"
        }
    }

    private func supportDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diff", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func persistSessionSoon() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            self.writeSession()
        }
    }

    private func persistState() {
        persistSessionSoon()
    }

    private func writeSession() {
        let directory = supportDirectory()
        try? leftText.write(to: directory.appendingPathComponent("left.txt"), atomically: true, encoding: .utf8)
        try? rightText.write(to: directory.appendingPathComponent("right.txt"), atomically: true, encoding: .utf8)
        let state: [String: Any] = [
            "ignoreWhitespace": ignoreWhitespace,
            "fontSize": fontSize,
            "scrollOffset": scrollOffset,
            "currentHunkIndex": currentHunkIndex,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted]) {
            try? data.write(to: directory.appendingPathComponent("state.json"), options: .atomic)
        }
    }

    private func loadPersistedSession() {
        if !leftText.isEmpty || !rightText.isEmpty { return }
        let directory = supportDirectory()
        if let left = try? String(contentsOf: directory.appendingPathComponent("left.txt"), encoding: .utf8) {
            leftText = left
        }
        if let right = try? String(contentsOf: directory.appendingPathComponent("right.txt"), encoding: .utf8) {
            rightText = right
        }
        if let data = try? Data(contentsOf: directory.appendingPathComponent("state.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let ignore = json["ignoreWhitespace"] as? Bool {
                ignoreWhitespace = ignore
            }
            if let size = json["fontSize"] as? Double {
                fontSize = size
            }
            if let offset = json["scrollOffset"] as? Double {
                scrollOffset = offset
            }
            if let hunk = json["currentHunkIndex"] as? Int {
                currentHunkIndex = hunk
            }
        }
    }
}
