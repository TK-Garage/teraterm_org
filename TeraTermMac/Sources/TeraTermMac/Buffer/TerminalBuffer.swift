/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of buffer.c to Swift/macOS
 * Terminal scroll buffer implementation
 */

import Foundation

// MARK: - Character Attributes (port of buffer.c character attribute flags)

struct CharAttributes: OptionSet, Codable, Equatable {
    let rawValue: UInt32

    static let bold       = CharAttributes(rawValue: 1 << 0)
    static let underline  = CharAttributes(rawValue: 1 << 1)
    static let blink      = CharAttributes(rawValue: 1 << 2)
    static let reverse    = CharAttributes(rawValue: 1 << 3)
    static let invisible  = CharAttributes(rawValue: 1 << 4)
    static let italic     = CharAttributes(rawValue: 1 << 5)
    static let strikethrough = CharAttributes(rawValue: 1 << 6)
    static let dim        = CharAttributes(rawValue: 1 << 7)
    static let protected_ = CharAttributes(rawValue: 1 << 8)
    static let wideChar   = CharAttributes(rawValue: 1 << 9)      // Wide character (occupies 2 cells)
    static let wideTrail  = CharAttributes(rawValue: 1 << 10)     // Second cell of wide char
    static let url        = CharAttributes(rawValue: 1 << 11)     // URL detected
    static let doubleUnderline = CharAttributes(rawValue: 1 << 12)
    static let curlyUnderline  = CharAttributes(rawValue: 1 << 13)
    static let dottedUnderline = CharAttributes(rawValue: 1 << 14)
    static let dashedUnderline = CharAttributes(rawValue: 1 << 15)
    static let overline        = CharAttributes(rawValue: 1 << 16)
}

// MARK: - Color Index

struct ColorIndex: Codable, Equatable {
    var foreground: UInt8 = 7     // Default white
    var background: UInt8 = 0     // Default black
    var isFgDefault: Bool = true
    var isBgDefault: Bool = true
    var isFg256: Bool = false     // xterm 256-color
    var isBg256: Bool = false
    var isFgRGB: Bool = false     // True color (24-bit)
    var isBgRGB: Bool = false
    var fgR: UInt8 = 255
    var fgG: UInt8 = 255
    var fgB: UInt8 = 255
    var bgR: UInt8 = 0
    var bgG: UInt8 = 0
    var bgB: UInt8 = 0

    static let `default` = ColorIndex()
}

// MARK: - Buffer Character (port of buff_char_t)

struct BufferCharacter: Equatable {
    var character: Character = " "
    var unicodeScalar: UnicodeScalar = " "
    var combiningCharacters: [UnicodeScalar] = []
    var attributes: CharAttributes = []
    var color: ColorIndex = .default
    var isModified: Bool = false

    var isEmpty: Bool {
        return character == " " && attributes.isEmpty && combiningCharacters.isEmpty
    }

    var isWide: Bool {
        return attributes.contains(.wideChar)
    }

    var isWideTrail: Bool {
        return attributes.contains(.wideTrail)
    }

    static let blank = BufferCharacter()

    static func == (lhs: BufferCharacter, rhs: BufferCharacter) -> Bool {
        return lhs.character == rhs.character &&
               lhs.attributes == rhs.attributes &&
               lhs.color == rhs.color &&
               lhs.combiningCharacters == rhs.combiningCharacters
    }
}

// MARK: - Buffer Line

struct BufferLine {
    var cells: [BufferCharacter]
    var isWrapped: Bool = false       // Line continues to next line
    var isModified: Bool = true

    init(width: Int) {
        cells = Array(repeating: .blank, count: width)
    }

    mutating func resize(to width: Int) {
        if width > cells.count {
            cells.append(contentsOf: Array(repeating: .blank, count: width - cells.count))
        } else if width < cells.count {
            cells = Array(cells.prefix(width))
        }
    }

    mutating func clear(from start: Int = 0, to end: Int? = nil) {
        let endIndex = end ?? cells.count
        for i in start..<min(endIndex, cells.count) {
            cells[i] = .blank
        }
        isModified = true
    }
}

// MARK: - Selection

struct BufferSelection {
    var startX: Int = 0
    var startY: Int = 0
    var endX: Int = 0
    var endY: Int = 0
    var isActive: Bool = false
    var isRectangular: Bool = false   // Box selection mode

    var normalized: (startX: Int, startY: Int, endX: Int, endY: Int) {
        if startY < endY || (startY == endY && startX <= endX) {
            return (startX, startY, endX, endY)
        } else {
            return (endX, endY, startX, startY)
        }
    }

    func contains(x: Int, y: Int) -> Bool {
        guard isActive else { return false }
        let sel = normalized
        if isRectangular {
            let minX = min(sel.startX, sel.endX)
            let maxX = max(sel.startX, sel.endX)
            return y >= sel.startY && y <= sel.endY && x >= minX && x <= maxX
        } else {
            if y < sel.startY || y > sel.endY { return false }
            if y == sel.startY && y == sel.endY { return x >= sel.startX && x < sel.endX }
            if y == sel.startY { return x >= sel.startX }
            if y == sel.endY { return x < sel.endX }
            return true
        }
    }
}

// MARK: - Tab Stops

struct TabStops {
    private var stops: Set<Int>
    var defaultInterval: Int = 8

    init(width: Int, interval: Int = 8) {
        defaultInterval = interval
        stops = Set<Int>()
        for i in stride(from: interval, to: width, by: interval) {
            stops.insert(i)
        }
    }

    func nextStop(from position: Int) -> Int {
        let sorted = stops.sorted()
        for stop in sorted {
            if stop > position { return stop }
        }
        return position
    }

    func prevStop(from position: Int) -> Int {
        let sorted = stops.sorted().reversed()
        for stop in sorted {
            if stop < position { return stop }
        }
        return 0
    }

    mutating func set(at position: Int) {
        stops.insert(position)
    }

    mutating func clear(at position: Int) {
        stops.remove(position)
    }

    mutating func clearAll() {
        stops.removeAll()
    }

    mutating func reset(width: Int) {
        stops.removeAll()
        for i in stride(from: defaultInterval, to: width, by: defaultInterval) {
            stops.insert(i)
        }
    }
}

// MARK: - Terminal Buffer (port of buffer.c)

class TerminalBuffer {
    // Buffer dimensions
    private(set) var width: Int
    private(set) var height: Int
    private(set) var scrollBufferSize: Int

    // Buffer storage
    private var lines: [BufferLine]
    private var altLines: [BufferLine]?  // Alternate screen buffer

    // Cursor position
    var cursorX: Int = 0
    var cursorY: Int = 0
    var savedCursorX: Int = 0
    var savedCursorY: Int = 0
    var savedAttributes: CharAttributes = []
    var savedColor: ColorIndex = .default

    // Alt buffer saved cursor
    var altSavedCursorX: Int = 0
    var altSavedCursorY: Int = 0

    // Scroll region
    var scrollTop: Int = 0
    var scrollBottom: Int
    var scrollLeft: Int = 0
    var scrollRight: Int

    // Current attributes
    var currentAttributes: CharAttributes = []
    var currentColor: ColorIndex = .default

    // Tab stops
    var tabStops: TabStops

    // Selection
    var selection: BufferSelection = BufferSelection()

    // Scroll position (for scroll-back viewing)
    var scrollOffset: Int = 0

    // Wrap state
    var wrapPending: Bool = false

    // Margins
    var useLeftRightMargin: Bool = false

    // Origin mode
    var originMode: Bool = false

    // Status
    var isAlternateBuffer: Bool = false

    // Callbacks
    var onBufferChanged: (() -> Void)?
    var onScrolled: ((Int) -> Void)?

    init(width: Int = 80, height: Int = 24, scrollBufferSize: Int = 10000) {
        self.width = width
        self.height = height
        self.scrollBufferSize = scrollBufferSize
        self.scrollBottom = height - 1
        self.scrollRight = width - 1
        self.tabStops = TabStops(width: width)

        self.lines = []
        for _ in 0..<height {
            self.lines.append(BufferLine(width: width))
        }
    }

    // MARK: - Buffer Access

    var totalLines: Int {
        return lines.count
    }

    var visibleStartLine: Int {
        return max(0, lines.count - height)
    }

    func line(at index: Int) -> BufferLine? {
        let absoluteIndex = visibleStartLine + index - scrollOffset
        guard absoluteIndex >= 0 && absoluteIndex < lines.count else { return nil }
        return lines[absoluteIndex]
    }

    func absoluteLine(at index: Int) -> BufferLine? {
        guard index >= 0 && index < lines.count else { return nil }
        return lines[index]
    }

    func character(at x: Int, y: Int) -> BufferCharacter {
        guard let line = self.line(at: y), x >= 0 && x < line.cells.count else {
            return .blank
        }
        return line.cells[x]
    }

    // MARK: - Character Writing

    func putChar(_ char: Character, scalar: UnicodeScalar? = nil) {
        guard cursorY >= 0 && cursorY < height else { return }

        if wrapPending {
            wrapPending = false
            let lineIndex = visibleStartLine + cursorY
            if lineIndex >= 0 && lineIndex < lines.count {
                lines[lineIndex].isWrapped = true
            }
            carriageReturn()
            lineFeed()
        }

        let lineIndex = visibleStartLine + cursorY
        guard lineIndex >= 0 && lineIndex < lines.count else { return }
        guard cursorX >= 0 && cursorX < width else { return }

        var ch = BufferCharacter()
        ch.character = char
        ch.unicodeScalar = scalar ?? char.unicodeScalars.first ?? " "
        ch.attributes = currentAttributes
        ch.color = currentColor
        ch.isModified = true

        // Check if wide character
        let charWidth = characterWidth(of: ch.unicodeScalar)
        if charWidth == 2 {
            ch.attributes.insert(.wideChar)
            if cursorX + 1 < width {
                lines[lineIndex].cells[cursorX] = ch
                var trail = BufferCharacter.blank
                trail.attributes = [.wideTrail]
                trail.color = currentColor
                lines[lineIndex].cells[cursorX + 1] = trail
                lines[lineIndex].isModified = true
                cursorX += 2
            } else {
                // Wide char at edge - put space and wrap
                lines[lineIndex].cells[cursorX] = .blank
                wrapPending = true
                return
            }
        } else {
            // Clear wide char trail if overwriting
            if cursorX > 0 && lines[lineIndex].cells[cursorX].isWideTrail {
                lines[lineIndex].cells[cursorX - 1] = .blank
            }
            if cursorX + 1 < width && lines[lineIndex].cells[cursorX].isWide {
                lines[lineIndex].cells[cursorX + 1] = .blank
            }

            lines[lineIndex].cells[cursorX] = ch
            lines[lineIndex].isModified = true
            cursorX += 1
        }

        if cursorX >= width {
            cursorX = width - 1
            wrapPending = true
        }
    }

    func addCombiningCharacter(_ scalar: UnicodeScalar) {
        let lineIndex = visibleStartLine + cursorY
        guard lineIndex >= 0 && lineIndex < lines.count else { return }
        let prevX = max(0, cursorX - 1)
        guard prevX < width else { return }
        lines[lineIndex].cells[prevX].combiningCharacters.append(scalar)
        lines[lineIndex].isModified = true
    }

    // MARK: - Cursor Movement

    func moveCursorTo(x: Int, y: Int) {
        wrapPending = false
        if originMode {
            cursorX = max(scrollLeft, min(x + scrollLeft, scrollRight))
            cursorY = max(scrollTop, min(y + scrollTop, scrollBottom))
        } else {
            cursorX = max(0, min(x, width - 1))
            cursorY = max(0, min(y, height - 1))
        }
    }

    func moveCursorUp(_ n: Int = 1) {
        wrapPending = false
        cursorY = max(scrollTop, cursorY - n)
    }

    func moveCursorDown(_ n: Int = 1) {
        wrapPending = false
        cursorY = min(scrollBottom, cursorY + n)
    }

    func moveCursorForward(_ n: Int = 1) {
        wrapPending = false
        cursorX = min(width - 1, cursorX + n)
    }

    func moveCursorBackward(_ n: Int = 1) {
        wrapPending = false
        cursorX = max(0, cursorX - n)
    }

    func carriageReturn() {
        wrapPending = false
        cursorX = useLeftRightMargin ? scrollLeft : 0
    }

    func lineFeed() {
        wrapPending = false
        if cursorY == scrollBottom {
            scrollUp(1)
        } else if cursorY < height - 1 {
            cursorY += 1
        }
    }

    func reverseLineFeed() {
        wrapPending = false
        if cursorY == scrollTop {
            scrollDown(1)
        } else if cursorY > 0 {
            cursorY -= 1
        }
    }

    func tab() {
        wrapPending = false
        let nextTab = tabStops.nextStop(from: cursorX)
        cursorX = min(nextTab, width - 1)
    }

    func backTab() {
        wrapPending = false
        let prevTab = tabStops.prevStop(from: cursorX)
        cursorX = max(prevTab, 0)
    }

    func backspace() {
        wrapPending = false
        if cursorX > 0 {
            cursorX -= 1
        }
    }

    // MARK: - Save/Restore Cursor

    func saveCursor() {
        savedCursorX = cursorX
        savedCursorY = cursorY
        savedAttributes = currentAttributes
        savedColor = currentColor
    }

    func restoreCursor() {
        cursorX = savedCursorX
        cursorY = savedCursorY
        currentAttributes = savedAttributes
        currentColor = savedColor
        wrapPending = false
    }

    // MARK: - Scrolling

    func scrollUp(_ n: Int = 1) {
        for _ in 0..<n {
            if scrollTop == 0 && scrollBottom == height - 1 {
                // Full screen scroll - add to scroll buffer
                lines.append(BufferLine(width: width))

                // Trim scroll buffer if needed
                let maxLines = height + scrollBufferSize
                if lines.count > maxLines {
                    lines.removeFirst(lines.count - maxLines)
                }
            } else {
                // Region scroll
                let startLine = visibleStartLine + scrollTop
                let endLine = visibleStartLine + scrollBottom
                guard startLine >= 0 && endLine < lines.count else { continue }

                lines.remove(at: startLine)
                lines.insert(BufferLine(width: width), at: endLine)
            }
        }
        onScrolled?(n)
    }

    func scrollDown(_ n: Int = 1) {
        for _ in 0..<n {
            let startLine = visibleStartLine + scrollTop
            let endLine = visibleStartLine + scrollBottom
            guard startLine >= 0 && endLine < lines.count else { continue }

            lines.remove(at: endLine)
            lines.insert(BufferLine(width: width), at: startLine)
        }
    }

    func scrollLeft(_ n: Int = 1) {
        for row in scrollTop...scrollBottom {
            let lineIndex = visibleStartLine + row
            guard lineIndex >= 0 && lineIndex < lines.count else { continue }
            let left = useLeftRightMargin ? scrollLeft : 0
            let right = useLeftRightMargin ? scrollRight : width - 1
            for x in left..<right {
                let srcX = x + n
                if srcX <= right {
                    lines[lineIndex].cells[x] = lines[lineIndex].cells[srcX]
                } else {
                    lines[lineIndex].cells[x] = .blank
                }
            }
            lines[lineIndex].isModified = true
        }
    }

    func scrollRight(_ n: Int = 1) {
        for row in scrollTop...scrollBottom {
            let lineIndex = visibleStartLine + row
            guard lineIndex >= 0 && lineIndex < lines.count else { continue }
            let left = useLeftRightMargin ? scrollLeft : 0
            let right = useLeftRightMargin ? scrollRight : width - 1
            for x in stride(from: right, through: left, by: -1) {
                let srcX = x - n
                if srcX >= left {
                    lines[lineIndex].cells[x] = lines[lineIndex].cells[srcX]
                } else {
                    lines[lineIndex].cells[x] = .blank
                }
            }
            lines[lineIndex].isModified = true
        }
    }

    // MARK: - Erase Operations

    func eraseInDisplay(_ mode: Int) {
        switch mode {
        case 0: // Erase below (including cursor)
            eraseInLine(0)
            for row in (cursorY + 1)..<height {
                let lineIndex = visibleStartLine + row
                if lineIndex >= 0 && lineIndex < lines.count {
                    lines[lineIndex].clear()
                }
            }
        case 1: // Erase above (including cursor)
            eraseInLine(1)
            for row in 0..<cursorY {
                let lineIndex = visibleStartLine + row
                if lineIndex >= 0 && lineIndex < lines.count {
                    lines[lineIndex].clear()
                }
            }
        case 2: // Erase all
            for row in 0..<height {
                let lineIndex = visibleStartLine + row
                if lineIndex >= 0 && lineIndex < lines.count {
                    lines[lineIndex].clear()
                }
            }
        case 3: // Erase scrollback buffer
            let visibleLines = Array(lines.suffix(height))
            lines = visibleLines
            scrollOffset = 0
        default:
            break
        }
    }

    func eraseInLine(_ mode: Int) {
        let lineIndex = visibleStartLine + cursorY
        guard lineIndex >= 0 && lineIndex < lines.count else { return }

        switch mode {
        case 0: // Erase to right (including cursor)
            lines[lineIndex].clear(from: cursorX)
        case 1: // Erase to left (including cursor)
            lines[lineIndex].clear(from: 0, to: cursorX + 1)
        case 2: // Erase entire line
            lines[lineIndex].clear()
        default:
            break
        }
    }

    func eraseCharacters(_ n: Int) {
        let lineIndex = visibleStartLine + cursorY
        guard lineIndex >= 0 && lineIndex < lines.count else { return }
        let end = min(cursorX + n, width)
        lines[lineIndex].clear(from: cursorX, to: end)
    }

    // MARK: - Insert/Delete

    func insertLines(_ n: Int) {
        wrapPending = false
        guard cursorY >= scrollTop && cursorY <= scrollBottom else { return }
        for _ in 0..<n {
            let endLine = visibleStartLine + scrollBottom
            let insertLine = visibleStartLine + cursorY
            guard endLine < lines.count && insertLine < lines.count else { continue }
            lines.remove(at: endLine)
            lines.insert(BufferLine(width: width), at: insertLine)
        }
    }

    func deleteLines(_ n: Int) {
        wrapPending = false
        guard cursorY >= scrollTop && cursorY <= scrollBottom else { return }
        for _ in 0..<n {
            let deleteLine = visibleStartLine + cursorY
            let endLine = visibleStartLine + scrollBottom
            guard deleteLine < lines.count && endLine < lines.count else { continue }
            lines.remove(at: deleteLine)
            lines.insert(BufferLine(width: width), at: endLine)
        }
    }

    func insertCharacters(_ n: Int) {
        let lineIndex = visibleStartLine + cursorY
        guard lineIndex >= 0 && lineIndex < lines.count else { return }
        let rightEdge = useLeftRightMargin ? scrollRight : width - 1
        for _ in 0..<n {
            if cursorX <= rightEdge {
                lines[lineIndex].cells.remove(at: min(rightEdge, lines[lineIndex].cells.count - 1))
                lines[lineIndex].cells.insert(.blank, at: cursorX)
            }
        }
        // Ensure correct count
        while lines[lineIndex].cells.count < width {
            lines[lineIndex].cells.append(.blank)
        }
        while lines[lineIndex].cells.count > width {
            lines[lineIndex].cells.removeLast()
        }
        lines[lineIndex].isModified = true
    }

    func deleteCharacters(_ n: Int) {
        let lineIndex = visibleStartLine + cursorY
        guard lineIndex >= 0 && lineIndex < lines.count else { return }
        let rightEdge = useLeftRightMargin ? scrollRight : width - 1
        for _ in 0..<n {
            if cursorX < lines[lineIndex].cells.count {
                lines[lineIndex].cells.remove(at: cursorX)
                lines[lineIndex].cells.insert(.blank, at: min(rightEdge, lines[lineIndex].cells.count))
            }
        }
        while lines[lineIndex].cells.count < width {
            lines[lineIndex].cells.append(.blank)
        }
        while lines[lineIndex].cells.count > width {
            lines[lineIndex].cells.removeLast()
        }
        lines[lineIndex].isModified = true
    }

    // MARK: - Alternate Buffer

    func switchToAlternateBuffer() {
        guard !isAlternateBuffer else { return }
        altSavedCursorX = cursorX
        altSavedCursorY = cursorY
        altLines = Array(lines.suffix(height))
        // Create clean alternate buffer
        for i in (lines.count - height)..<lines.count {
            lines[i] = BufferLine(width: width)
        }
        isAlternateBuffer = true
    }

    func switchToNormalBuffer() {
        guard isAlternateBuffer else { return }
        if let alt = altLines {
            let scrollBack = Array(lines.prefix(lines.count - height))
            lines = scrollBack + alt
        }
        cursorX = altSavedCursorX
        cursorY = altSavedCursorY
        altLines = nil
        isAlternateBuffer = false
    }

    // MARK: - Resize

    func resize(newWidth: Int, newHeight: Int) {
        let oldWidth = width
        let oldHeight = height
        width = newWidth
        height = newHeight

        // Resize existing lines
        for i in 0..<lines.count {
            lines[i].resize(to: newWidth)
        }

        // Ensure we have enough lines for the screen
        while lines.count < height {
            lines.append(BufferLine(width: newWidth))
        }

        // Adjust scroll region
        if scrollBottom == oldHeight - 1 {
            scrollBottom = newHeight - 1
        } else {
            scrollBottom = min(scrollBottom, newHeight - 1)
        }
        if scrollRight == oldWidth - 1 {
            scrollRight = newWidth - 1
        } else {
            scrollRight = min(scrollRight, newWidth - 1)
        }

        scrollTop = min(scrollTop, newHeight - 1)

        // Adjust cursor
        cursorX = min(cursorX, newWidth - 1)
        cursorY = min(cursorY, newHeight - 1)

        // Reset tab stops
        tabStops.reset(width: newWidth)

        onBufferChanged?()
    }

    // MARK: - Set Scroll Region

    func setScrollRegion(top: Int, bottom: Int) {
        let t = max(0, top)
        let b = min(height - 1, bottom)
        guard t < b else { return }
        scrollTop = t
        scrollBottom = b
        if originMode {
            cursorX = scrollLeft
            cursorY = scrollTop
        } else {
            cursorX = 0
            cursorY = 0
        }
        wrapPending = false
    }

    func setLeftRightMargin(left: Int, right: Int) {
        let l = max(0, left)
        let r = min(width - 1, right)
        guard l < r else { return }
        scrollLeft = l
        scrollRight = r
        useLeftRightMargin = true
        if originMode {
            cursorX = scrollLeft
            cursorY = scrollTop
        } else {
            cursorX = 0
            cursorY = 0
        }
        wrapPending = false
    }

    // MARK: - Selection / Copy

    func getSelectedText() -> String? {
        guard selection.isActive else { return nil }
        let sel = selection.normalized
        var result = ""

        for row in sel.startY...sel.endY {
            let lineIndex = visibleStartLine + row - scrollOffset
            guard lineIndex >= 0 && lineIndex < lines.count else { continue }
            let line = lines[lineIndex]

            let startCol = (row == sel.startY) ? sel.startX : 0
            let endCol = (row == sel.endY) ? sel.endX : width

            for col in startCol..<min(endCol, line.cells.count) {
                let cell = line.cells[col]
                if cell.isWideTrail { continue }
                result.append(cell.character)
            }

            if row < sel.endY && !line.isWrapped {
                result.append("\n")
            }
        }

        return result.isEmpty ? nil : result
    }

    // MARK: - Reset

    func reset() {
        lines = []
        for _ in 0..<height {
            lines.append(BufferLine(width: width))
        }
        cursorX = 0
        cursorY = 0
        scrollTop = 0
        scrollBottom = height - 1
        scrollLeft = 0
        scrollRight = width - 1
        scrollOffset = 0
        currentAttributes = []
        currentColor = .default
        selection = BufferSelection()
        tabStops.reset(width: width)
        wrapPending = false
        originMode = false
        useLeftRightMargin = false
        isAlternateBuffer = false
        altLines = nil
        onBufferChanged?()
    }

    // MARK: - Character Width

    private func characterWidth(of scalar: UnicodeScalar) -> Int {
        let value = scalar.value
        // Control characters
        if value < 0x20 || (value >= 0x7F && value < 0xA0) { return 0 }
        // CJK Unified Ideographs
        if (value >= 0x4E00 && value <= 0x9FFF) ||
           (value >= 0x3400 && value <= 0x4DBF) ||
           (value >= 0x20000 && value <= 0x2A6DF) ||
           (value >= 0x2A700 && value <= 0x2B73F) ||
           (value >= 0x2B740 && value <= 0x2B81F) ||
           (value >= 0x2B820 && value <= 0x2CEAF) ||
           (value >= 0xF900 && value <= 0xFAFF) ||
           (value >= 0x2F800 && value <= 0x2FA1F) {
            return 2
        }
        // Fullwidth forms
        if (value >= 0xFF01 && value <= 0xFF60) ||
           (value >= 0xFFE0 && value <= 0xFFE6) {
            return 2
        }
        // Hangul
        if (value >= 0xAC00 && value <= 0xD7AF) ||
           (value >= 0x1100 && value <= 0x115F) ||
           (value >= 0x2329 && value <= 0x232A) ||
           (value >= 0x2E80 && value <= 0x303E) ||
           (value >= 0x3041 && value <= 0x33BF) ||
           (value >= 0xFE10 && value <= 0xFE6F) {
            return 2
        }
        return 1
    }
}
