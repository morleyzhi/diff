import Foundation

enum DiffKind: Sendable, Equatable {
    case equal
    case insert
    case delete
    case replace
}

struct DiffRow: Sendable {
    let kind: DiffKind
    let left: String?
    let right: String?
    let leftChanges: [Range<Int>]
    let rightChanges: [Range<Int>]
    let leftNumber: Int?
    let rightNumber: Int?
}

struct DiffHunk: Sendable {
    let rows: Range<Int>
    let hasDelete: Bool
    let hasInsert: Bool
}

struct DiffResult: Sendable {
    let rows: [DiffRow]
    let hunks: [DiffHunk]
    let maxLeftChars: Int
    let maxRightChars: Int
    let identical: Bool
}

enum DiffEngine {
    static let tabWidth = 4
    static let charDiffLimit = 8_000

    static func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }

    static func expandTabs(_ text: String) -> String {
        if !text.contains("\t") { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var column = 0
        for character in text {
            if character == "\t" {
                let spaces = Self.tabWidth - (column % Self.tabWidth)
                result.append(String(repeating: " ", count: spaces))
                column += spaces
            } else {
                result.append(character)
                column += 1
            }
        }
        return result
    }

    static func normalize(_ line: String, ignoreWhitespace: Bool) -> String {
        if !ignoreWhitespace { return line }
        return String(line.filter { !$0.isWhitespace })
    }

    static func diff(left: String, right: String, ignoreWhitespace: Bool) -> DiffResult {
        // Keep original line text so editor highlight ranges match the textarea.
        let leftLines = splitLines(left)
        let rightLines = splitLines(right)
        return diffLines(leftLines, rightLines, ignoreWhitespace: ignoreWhitespace)
    }

    static func diffLines(_ leftLines: [String], _ rightLines: [String], ignoreWhitespace: Bool) -> DiffResult {
        let leftKeys = leftLines.map { normalize($0, ignoreWhitespace: ignoreWhitespace) }
        let rightKeys = rightLines.map { normalize($0, ignoreWhitespace: ignoreWhitespace) }
        let difference = rightKeys.difference(from: leftKeys)

        var removalOffsets = Set<Int>()
        removalOffsets.reserveCapacity(difference.removals.count)
        var insertionOffsets = Set<Int>()
        insertionOffsets.reserveCapacity(difference.insertions.count)

        for change in difference {
            switch change {
            case .remove(let offset, _, _):
                removalOffsets.insert(offset)
            case .insert(let offset, _, _):
                insertionOffsets.insert(offset)
            }
        }

        var rows: [DiffRow] = []
        rows.reserveCapacity(leftLines.count + rightLines.count)
        var leftIndex = 0
        var rightIndex = 0
        var leftNumber = 1
        var rightNumber = 1
        var maxLeftChars = 0
        var maxRightChars = 0

        while leftIndex < leftLines.count || rightIndex < rightLines.count {
            let isRemoval = leftIndex < leftLines.count && removalOffsets.contains(leftIndex)
            let isInsertion = rightIndex < rightLines.count && insertionOffsets.contains(rightIndex)

            if leftIndex < leftLines.count, rightIndex < rightLines.count, !isRemoval, !isInsertion {
                let leftLine = leftLines[leftIndex]
                let rightLine = rightLines[rightIndex]
                maxLeftChars = max(maxLeftChars, leftLine.count)
                maxRightChars = max(maxRightChars, rightLine.count)
                rows.append(
                    DiffRow(
                        kind: .equal,
                        left: leftLine,
                        right: rightLine,
                        leftChanges: [],
                        rightChanges: [],
                        leftNumber: leftNumber,
                        rightNumber: rightNumber
                    )
                )
                leftIndex += 1
                rightIndex += 1
                leftNumber += 1
                rightNumber += 1
                continue
            }

            if isRemoval && isInsertion {
                let leftLine = leftLines[leftIndex]
                let rightLine = rightLines[rightIndex]
                let changes = characterChanges(left: leftLine, right: rightLine, ignoreWhitespace: ignoreWhitespace)
                maxLeftChars = max(maxLeftChars, leftLine.count)
                maxRightChars = max(maxRightChars, rightLine.count)
                rows.append(
                    DiffRow(
                        kind: .replace,
                        left: leftLine,
                        right: rightLine,
                        leftChanges: changes.left,
                        rightChanges: changes.right,
                        leftNumber: leftNumber,
                        rightNumber: rightNumber
                    )
                )
                leftIndex += 1
                rightIndex += 1
                leftNumber += 1
                rightNumber += 1
                continue
            }

            if isRemoval {
                let leftLine = leftLines[leftIndex]
                maxLeftChars = max(maxLeftChars, leftLine.count)
                rows.append(
                    DiffRow(
                        kind: .delete,
                        left: leftLine,
                        right: nil,
                        leftChanges: [0..<leftLine.count],
                        rightChanges: [],
                        leftNumber: leftNumber,
                        rightNumber: nil
                    )
                )
                leftIndex += 1
                leftNumber += 1
                continue
            }

            if isInsertion {
                let rightLine = rightLines[rightIndex]
                maxRightChars = max(maxRightChars, rightLine.count)
                rows.append(
                    DiffRow(
                        kind: .insert,
                        left: nil,
                        right: rightLine,
                        leftChanges: [],
                        rightChanges: [0..<rightLine.count],
                        leftNumber: nil,
                        rightNumber: rightNumber
                    )
                )
                rightIndex += 1
                rightNumber += 1
                continue
            }

            break
        }

        let hunks = hunks(in: rows)
        let identical = hunks.isEmpty && !leftLines.isEmpty && leftLines.count == rightLines.count
        return DiffResult(
            rows: rows,
            hunks: hunks,
            maxLeftChars: maxLeftChars,
            maxRightChars: maxRightChars,
            identical: identical || (leftLines.isEmpty && rightLines.isEmpty)
        )
    }

    static func characterChanges(left: String, right: String, ignoreWhitespace: Bool) -> (left: [Range<Int>], right: [Range<Int>]) {
        if left.count > charDiffLimit || right.count > charDiffLimit {
            return ([0..<left.count], [0..<right.count])
        }

        let leftChars = Array(left)
        let rightChars = Array(right)
        let difference = rightChars.difference(from: leftChars)
        var leftRanges: [Range<Int>] = []
        var rightRanges: [Range<Int>] = []

        for change in difference {
            switch change {
            case .remove(let offset, _, _):
                leftRanges.append(offset..<(offset + 1))
            case .insert(let offset, _, _):
                rightRanges.append(offset..<(offset + 1))
            }
        }

        var mergedLeft = merge(leftRanges)
        var mergedRight = merge(rightRanges)
        if ignoreWhitespace {
            mergedLeft = stripWhitespaceOnly(ranges: mergedLeft, in: leftChars)
            mergedRight = stripWhitespaceOnly(ranges: mergedRight, in: rightChars)
        }
        return (mergedLeft, mergedRight)
    }

    static func merge(_ ranges: [Range<Int>]) -> [Range<Int>] {
        if ranges.isEmpty { return [] }
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<Int>] = [sorted[0]]
        for range in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            if last.upperBound >= range.lowerBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    static func stripWhitespaceOnly(ranges: [Range<Int>], in characters: [Character]) -> [Range<Int>] {
        ranges.filter { range in
            if range.isEmpty { return false }
            let upper = min(range.upperBound, characters.count)
            let lower = min(range.lowerBound, upper)
            if lower >= upper { return false }
            return !characters[lower..<upper].allSatisfy(\.isWhitespace)
        }
    }

    static func hunks(in rows: [DiffRow]) -> [DiffHunk] {
        var result: [DiffHunk] = []
        var start: Int?
        var hasDelete = false
        var hasInsert = false

        func close(at end: Int) {
            guard let start else { return }
            result.append(DiffHunk(rows: start..<end, hasDelete: hasDelete, hasInsert: hasInsert))
        }

        for (index, row) in rows.enumerated() {
            if row.kind == .equal {
                if start != nil {
                    close(at: index)
                    start = nil
                    hasDelete = false
                    hasInsert = false
                }
                continue
            }
            if start == nil { start = index }
            if row.kind == .delete || row.kind == .replace { hasDelete = true }
            if row.kind == .insert || row.kind == .replace { hasInsert = true }
        }
        if start != nil { close(at: rows.count) }
        return result
    }

    static func runSelfTests() -> Bool {
        var failed = 0

        func expect(_ name: String, _ condition: @autoclosure () -> Bool) {
            if !condition() {
                fputs("FAIL: \(name)\n", stderr)
                failed += 1
            }
        }

        let basic = diff(left: "a\nb\nc", right: "a\nx\nc", ignoreWhitespace: true)
        expect("basic row count", basic.rows.count == 3)
        expect("basic middle replace", basic.rows[1].kind == .replace)
        expect("basic one hunk", basic.hunks.count == 1)
        expect("basic not identical", basic.identical == false)

        let whitespace = diff(left: "hello  world", right: "hello world", ignoreWhitespace: true)
        expect("ignore whitespace equal", whitespace.identical)
        expect("ignore whitespace no hunks", whitespace.hunks.isEmpty)

        let whitespaceOff = diff(left: "hello  world", right: "hello world", ignoreWhitespace: false)
        expect("whitespace detected when off", whitespaceOff.hunks.count == 1)

        let insert = diff(left: "a\nc\n", right: "a\nb\nc\n", ignoreWhitespace: true)
        expect("insert kind", insert.rows.contains { $0.kind == .insert && $0.right == "b" })

        let delete = diff(left: "a\nb\nc\n", right: "a\nc\n", ignoreWhitespace: true)
        expect("delete kind", delete.rows.contains { $0.kind == .delete && $0.left == "b" })

        let chars = characterChanges(left: "hello", right: "hallo", ignoreWhitespace: false)
        expect("char left change", chars.left == [1..<2])
        expect("char right change", chars.right == [1..<2])

        let empty = diff(left: "", right: "", ignoreWhitespace: true)
        expect("empty identical", empty.identical)

        let crlf = splitLines("a\r\nb\r\n")
        expect("crlf lines", crlf == ["a", "b", ""])

        let tabs = expandTabs("a\tb")
        expect("tab expansion", tabs == "a   b")

        return failed == 0
    }
}
