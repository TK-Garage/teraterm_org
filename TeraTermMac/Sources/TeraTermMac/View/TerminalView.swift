/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of vtdisp.c to Swift/macOS
 * Terminal display view using AppKit + Core Text
 */

#if canImport(AppKit)
import AppKit
import CoreText

// MARK: - Localization Helper

private func L(_ key: String) -> String {
    #if SWIFT_PACKAGE
    return NSLocalizedString(key, bundle: Bundle.module, comment: "")
    #else
    return NSLocalizedString(key, bundle: Bundle.main, comment: "")
    #endif
}

// MARK: - Terminal View Delegate

protocol TerminalViewDelegate: AnyObject {
    func terminalViewDidReceiveKeyEvent(_ event: TerminalKeyEvent)
    func terminalViewDidReceiveMouseEvent(button: Int, x: Int, y: Int, isRelease: Bool, modifiers: TerminalKeyEvent.KeyModifiers)
    func terminalViewDidReceiveScrollEvent(direction: Int, x: Int, y: Int, modifiers: TerminalKeyEvent.KeyModifiers)
    func terminalViewDidResize(columns: Int, rows: Int)
    func terminalViewDidRequestPaste(_ text: String)
    func terminalViewDidGainFocus()
    func terminalViewDidLoseFocus()
}

// MARK: - Terminal View (port of vtdisp.c)

class TerminalView: NSView {
    weak var terminalDelegate: TerminalViewDelegate?

    var buffer: TerminalBuffer?
    var settings: TerminalSettings = TerminalSettings()
    var modes: TerminalModes = TerminalModes()

    // Font metrics
    private(set) var cellWidth: CGFloat = 8.0
    private(set) var cellHeight: CGFloat = 16.0
    private(set) var fontAscent: CGFloat = 12.0
    private(set) var fontDescent: CGFloat = 4.0
    private var ctFont: CTFont?
    private var boldFont: CTFont?
    private var italicFont: CTFont?

    // Display state
    private var columns: Int = 80
    private var rows: Int = 24

    // Cursor blink
    private var cursorVisible: Bool = true
    private var cursorBlinkTimer: Timer?

    // Selection state
    private var isSelecting: Bool = false
    private var selectionStart: (x: Int, y: Int) = (0, 0)

    // 256-color palette cache
    private var colorPalette: [NSColor] = []

    // Content inset to avoid titlebar / window rounded corners
    var topInset: CGFloat = 0

    // Scroll
    private var scrollbackOffset: Int = 0

    // IME
    private var markedText: NSMutableAttributedString?
    private var imeMarkedRange: NSRange = NSRange(location: NSNotFound, length: 0)
    private var _selectedRange: NSRange = NSRange(location: 0, length: 0)

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        // Use clear background so NSVisualEffectView glass effect shows through.
        // The terminal background is drawn in draw() with configurable alpha.
        layer?.backgroundColor = NSColor.clear.cgColor

        // Build 256-color palette
        build256ColorPalette()

        updateFont()
        startCursorBlink()
    }

    deinit {
        cursorBlinkTimer?.invalidate()
    }

    // MARK: - Font Setup (port of vtdisp.c font handling)

    func updateFont() {
        let font = NSFont(name: settings.fontName, size: CGFloat(settings.fontSize))
            ?? NSFont.monospacedSystemFont(ofSize: CGFloat(settings.fontSize), weight: .regular)

        ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)

        // Create bold variant
        if let ct = ctFont {
            boldFont = CTFontCreateCopyWithSymbolicTraits(ct, 0, nil, .boldTrait, .boldTrait)
                ?? CTFontCreateCopyWithAttributes(ct, 0, nil, nil)
            italicFont = CTFontCreateCopyWithSymbolicTraits(ct, 0, nil, .italicTrait, .italicTrait)
                ?? CTFontCreateCopyWithAttributes(ct, 0, nil, nil)
        }

        // Calculate cell metrics
        let ascent = CTFontGetAscent(ctFont!)
        let descent = CTFontGetDescent(ctFont!)
        let leading = CTFontGetLeading(ctFont!)

        fontAscent = ceil(ascent)
        fontDescent = ceil(descent)
        cellHeight = ceil(ascent + descent + leading)

        // Measure 'M' width for cell width
        var glyph = CGGlyph()
        let chars: [UniChar] = Array("M".utf16)
        CTFontGetGlyphsForCharacters(ctFont!, chars, &glyph, 1)
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(ctFont!, .horizontal, &glyph, &advance, 1)
        cellWidth = ceil(advance.width)

        if cellWidth < 1 { cellWidth = ceil(CGFloat(settings.fontSize) * 0.6) }
        if cellHeight < 1 { cellHeight = ceil(CGFloat(settings.fontSize) * 1.2) }

        recalculateSize()
        needsDisplay = true
    }

    // MARK: - Size Calculation

    private func recalculateSize() {
        let availableHeight = bounds.height - topInset
        let newCols = max(1, Int(bounds.width / cellWidth))
        let newRows = max(1, Int(availableHeight / cellHeight))

        if newCols != columns || newRows != rows {
            columns = newCols
            rows = newRows
            terminalDelegate?.terminalViewDidResize(columns: columns, rows: rows)
        }
    }

    var terminalSize: (columns: Int, rows: Int) {
        return (columns, rows)
    }

    func preferredSize(columns: Int, rows: Int) -> NSSize {
        return NSSize(width: CGFloat(columns) * cellWidth, height: CGFloat(rows) * cellHeight + topInset)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        recalculateSize()
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        recalculateSize()
    }

    // MARK: - Drawing (port of vtdisp.c rendering)

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        guard let buffer = buffer else {
            // Draw empty screen
            context.setFillColor(backgroundColor.cgColor)
            context.fill(dirtyRect)
            return
        }

        // Draw background
        context.setFillColor(backgroundColor.cgColor)
        context.fill(bounds)

        // Draw each visible row
        for row in 0..<rows {
            guard let line = buffer.line(at: row) else { continue }
            drawLine(context: context, line: line, row: row, buffer: buffer)
        }

        // Draw cursor
        if modes.showCursor && cursorVisible {
            drawCursor(context: context, buffer: buffer)
        }

        // Draw selection overlay
        drawSelection(context: context, buffer: buffer)
    }

    private func drawLine(context: CGContext, line: BufferLine, row: Int, buffer: TerminalBuffer) {
        let y = topInset + CGFloat(row) * cellHeight

        for col in 0..<min(columns, line.cells.count) {
            let cell = line.cells[col]
            if cell.isWideTrail { continue }

            let x = CGFloat(col) * cellWidth
            let charWidth = cell.isWide ? cellWidth * 2 : cellWidth

            // Draw cell background
            let bgColor = resolveBackgroundColor(cell, inSelection: buffer.selection.contains(x: col, y: row))
            if bgColor != backgroundColor {
                context.setFillColor(bgColor.cgColor)
                context.fill(CGRect(x: x, y: y, width: charWidth, height: cellHeight))
            }

            // Draw character
            if cell.character != " " || !cell.combiningCharacters.isEmpty {
                let fgColor = resolveForegroundColor(cell, inSelection: buffer.selection.contains(x: col, y: row))
                drawCharacter(context: context, cell: cell, x: x, y: y, color: fgColor, width: charWidth)
            }

            // Draw underline styles
            drawDecorations(context: context, cell: cell, x: x, y: y, width: charWidth,
                          color: resolveForegroundColor(cell, inSelection: false))
        }
    }

    private func drawCharacter(context: CGContext, cell: BufferCharacter, x: CGFloat, y: CGFloat, color: NSColor, width: CGFloat) {
        guard let font = ctFont else { return }

        // Select font variant
        var drawFont = font
        if cell.attributes.contains(.bold), let bf = boldFont {
            drawFont = bf
        }
        if cell.attributes.contains(.italic), let itf = italicFont {
            drawFont = itf
        }

        // Build string with combining characters
        var str = String(cell.character)
        for combining in cell.combiningCharacters {
            str.append(Character(combining))
        }

        // Create attributed string
        let attributes: [NSAttributedString.Key: Any] = [
            .font: drawFont as Any,
            .foregroundColor: color,
        ]
        let attrStr = NSAttributedString(string: str, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrStr)

        // Draw
        context.saveGState()
        // Core Text draws with origin at bottom-left, but we're in flipped coordinates
        context.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
        context.textPosition = CGPoint(x: x, y: y + fontAscent)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawDecorations(context: CGContext, cell: BufferCharacter, x: CGFloat, y: CGFloat, width: CGFloat, color: NSColor) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1.0)

        if cell.attributes.contains(.underline) {
            let underlineY = y + fontAscent + 2
            context.move(to: CGPoint(x: x, y: underlineY))
            context.addLine(to: CGPoint(x: x + width, y: underlineY))
            context.strokePath()
        }

        if cell.attributes.contains(.doubleUnderline) {
            let underlineY = y + fontAscent + 1
            context.move(to: CGPoint(x: x, y: underlineY))
            context.addLine(to: CGPoint(x: x + width, y: underlineY))
            context.move(to: CGPoint(x: x, y: underlineY + 2))
            context.addLine(to: CGPoint(x: x + width, y: underlineY + 2))
            context.strokePath()
        }

        if cell.attributes.contains(.curlyUnderline) {
            let baseY = y + fontAscent + 2
            context.move(to: CGPoint(x: x, y: baseY))
            let steps = Int(width / 4)
            for i in 0...steps {
                let px = x + CGFloat(i) * 4
                let py = baseY + (i % 2 == 0 ? -1 : 1)
                context.addLine(to: CGPoint(x: px, y: py))
            }
            context.strokePath()
        }

        if cell.attributes.contains(.strikethrough) {
            let strikeY = y + cellHeight / 2
            context.move(to: CGPoint(x: x, y: strikeY))
            context.addLine(to: CGPoint(x: x + width, y: strikeY))
            context.strokePath()
        }

        if cell.attributes.contains(.overline) {
            let overlineY = y + 1
            context.move(to: CGPoint(x: x, y: overlineY))
            context.addLine(to: CGPoint(x: x + width, y: overlineY))
            context.strokePath()
        }
    }

    // MARK: - Cursor Drawing

    private func drawCursor(context: CGContext, buffer: TerminalBuffer) {
        let x = CGFloat(buffer.cursorX) * cellWidth
        let y = topInset + CGFloat(buffer.cursorY) * cellHeight
        let cursorColor = NSColor(
            red: CGFloat(settings.colorTheme.cursorColor.r) / 255.0,
            green: CGFloat(settings.colorTheme.cursorColor.g) / 255.0,
            blue: CGFloat(settings.colorTheme.cursorColor.b) / 255.0,
            alpha: 1.0
        )

        context.setStrokeColor(cursorColor.cgColor)
        context.setFillColor(cursorColor.cgColor)

        let rect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)

        switch settings.cursorShape {
        case .block:
            if window?.isKeyWindow == true {
                context.setFillColor(cursorColor.withAlphaComponent(0.5).cgColor)
                context.fill(rect)
            } else {
                context.setLineWidth(1.0)
                context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
            }
        case .vertical:
            context.fill(CGRect(x: x, y: y, width: 2, height: cellHeight))
        case .horizontal:
            context.fill(CGRect(x: x, y: y + cellHeight - 3, width: cellWidth, height: 3))
        }
    }

    // MARK: - Selection Drawing

    private func drawSelection(context: CGContext, buffer: TerminalBuffer) {
        guard buffer.selection.isActive else { return }
        let sel = buffer.selection.normalized

        let selColor = NSColor(
            red: CGFloat(settings.colorTheme.selectionBackground.r) / 255.0,
            green: CGFloat(settings.colorTheme.selectionBackground.g) / 255.0,
            blue: CGFloat(settings.colorTheme.selectionBackground.b) / 255.0,
            alpha: 0.3
        )
        context.setFillColor(selColor.cgColor)

        for row in max(0, sel.startY)...min(rows - 1, sel.endY) {
            let startCol = (row == sel.startY) ? sel.startX : 0
            let endCol = (row == sel.endY) ? sel.endX : columns
            let x = CGFloat(startCol) * cellWidth
            let y = topInset + CGFloat(row) * cellHeight
            let w = CGFloat(endCol - startCol) * cellWidth
            context.fill(CGRect(x: x, y: y, width: w, height: cellHeight))
        }
    }

    // MARK: - Color Resolution

    private var backgroundColor: NSColor {
        let c = modes.reverseVideo ? settings.colorTheme.foreground : settings.colorTheme.background
        // Use reduced alpha so the NSVisualEffectView glass effect bleeds through
        let glassAlpha = CGFloat(settings.windowAlpha) * 0.85
        return NSColor(
            red: CGFloat(c.r) / 255.0,
            green: CGFloat(c.g) / 255.0,
            blue: CGFloat(c.b) / 255.0,
            alpha: glassAlpha
        )
    }

    private func resolveBackgroundColor(_ cell: BufferCharacter, inSelection: Bool) -> NSColor {
        if inSelection {
            let c = settings.colorTheme.selectionBackground
            return NSColor(red: CGFloat(c.r) / 255.0, green: CGFloat(c.g) / 255.0, blue: CGFloat(c.b) / 255.0, alpha: 1.0)
        }

        let color = cell.color
        let attrs = cell.attributes

        // Handle reverse video
        let reversed = attrs.contains(.reverse) != modes.reverseVideo

        if reversed {
            // Use foreground as background
            if color.isFgRGB {
                return NSColor(red: CGFloat(color.fgR) / 255.0, green: CGFloat(color.fgG) / 255.0, blue: CGFloat(color.fgB) / 255.0, alpha: 1.0)
            } else if color.isFg256 || !color.isFgDefault {
                return palette256Color(Int(color.foreground))
            } else {
                let c = settings.colorTheme.foreground
                return NSColor(red: CGFloat(c.r) / 255.0, green: CGFloat(c.g) / 255.0, blue: CGFloat(c.b) / 255.0, alpha: 1.0)
            }
        }

        if color.isBgRGB {
            return NSColor(red: CGFloat(color.bgR) / 255.0, green: CGFloat(color.bgG) / 255.0, blue: CGFloat(color.bgB) / 255.0, alpha: 1.0)
        } else if color.isBg256 || !color.isBgDefault {
            return palette256Color(Int(color.background))
        }

        return backgroundColor
    }

    private func resolveForegroundColor(_ cell: BufferCharacter, inSelection: Bool) -> NSColor {
        if inSelection {
            let c = settings.colorTheme.selectionForeground
            return NSColor(red: CGFloat(c.r) / 255.0, green: CGFloat(c.g) / 255.0, blue: CGFloat(c.b) / 255.0, alpha: 1.0)
        }

        let color = cell.color
        let attrs = cell.attributes

        let reversed = attrs.contains(.reverse) != modes.reverseVideo

        if reversed {
            // Use background as foreground
            if color.isBgRGB {
                return NSColor(red: CGFloat(color.bgR) / 255.0, green: CGFloat(color.bgG) / 255.0, blue: CGFloat(color.bgB) / 255.0, alpha: 1.0)
            } else if color.isBg256 || !color.isBgDefault {
                return palette256Color(Int(color.background))
            } else {
                let c = settings.colorTheme.background
                return NSColor(red: CGFloat(c.r) / 255.0, green: CGFloat(c.g) / 255.0, blue: CGFloat(c.b) / 255.0, alpha: 1.0)
            }
        }

        if attrs.contains(.invisible) {
            return backgroundColor
        }

        var resultColor: NSColor

        if color.isFgRGB {
            resultColor = NSColor(red: CGFloat(color.fgR) / 255.0, green: CGFloat(color.fgG) / 255.0, blue: CGFloat(color.fgB) / 255.0, alpha: 1.0)
        } else if color.isFg256 || !color.isFgDefault {
            var idx = Int(color.foreground)
            // Bold brightens colors 0-7
            if attrs.contains(.bold) && idx < 8 {
                idx += 8
            }
            resultColor = palette256Color(idx)
        } else {
            let c = settings.colorTheme.foreground
            resultColor = NSColor(red: CGFloat(c.r) / 255.0, green: CGFloat(c.g) / 255.0, blue: CGFloat(c.b) / 255.0, alpha: 1.0)
        }

        if attrs.contains(.dim) {
            resultColor = resultColor.withAlphaComponent(0.5)
        }

        return resultColor
    }

    // MARK: - 256 Color Palette

    private func build256ColorPalette() {
        colorPalette = []

        // Colors 0-15: Standard ANSI colors from theme
        for i in 0..<16 {
            if i < settings.colorTheme.ansiColors.count {
                let c = settings.colorTheme.ansiColors[i]
                colorPalette.append(NSColor(red: CGFloat(c.r) / 255.0, green: CGFloat(c.g) / 255.0, blue: CGFloat(c.b) / 255.0, alpha: 1.0))
            } else {
                colorPalette.append(.white)
            }
        }

        // Colors 16-231: 6x6x6 color cube
        for r in 0..<6 {
            for g in 0..<6 {
                for b in 0..<6 {
                    let rv = r == 0 ? 0 : 55 + 40 * r
                    let gv = g == 0 ? 0 : 55 + 40 * g
                    let bv = b == 0 ? 0 : 55 + 40 * b
                    colorPalette.append(NSColor(red: CGFloat(rv) / 255.0, green: CGFloat(gv) / 255.0, blue: CGFloat(bv) / 255.0, alpha: 1.0))
                }
            }
        }

        // Colors 232-255: Grayscale
        for i in 0..<24 {
            let v = 8 + 10 * i
            colorPalette.append(NSColor(red: CGFloat(v) / 255.0, green: CGFloat(v) / 255.0, blue: CGFloat(v) / 255.0, alpha: 1.0))
        }
    }

    private func palette256Color(_ index: Int) -> NSColor {
        guard index >= 0 && index < colorPalette.count else { return .white }
        return colorPalette[index]
    }

    // MARK: - Cursor Blink

    private func startCursorBlink() {
        cursorBlinkTimer?.invalidate()
        if settings.cursorBlink {
            cursorBlinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.cursorVisible.toggle()
                self.setNeedsDisplay(self.cursorRect)
            }
        } else {
            cursorVisible = true
        }
    }

    private var cursorRect: NSRect {
        guard let buffer = buffer else { return .zero }
        let x = CGFloat(buffer.cursorX) * cellWidth
        let y = topInset + CGFloat(buffer.cursorY) * cellHeight
        return NSRect(x: x, y: y, width: cellWidth, height: cellHeight)
    }

    // MARK: - Key Event Handling

    override func keyDown(with event: NSEvent) {
        // IME変換中はすべてのキーをIMEに渡す
        if hasMarkedText() {
            interpretKeyEvents([event])
            return
        }

        // 特殊キー（Return、Backspace、矢印、Fnキーなど）はkeyCodeを保持して
        // 直接デリゲートに渡す。interpretKeyEvents経由だとkeyCodeが失われ、
        // CR/LF設定などの特殊処理が効かなくなるため。
        let keyCode = event.keyCode
        let isSpecialKey: Bool
        switch keyCode {
        case 0x24, 0x4C:  // Return, Enter (numpad)
            isSpecialKey = true
        case 0x33, 0x75:  // Backspace, Forward Delete
            isSpecialKey = true
        case 0x7E, 0x7D, 0x7B, 0x7C:  // Arrow keys
            isSpecialKey = true
        case 0x30, 0x35:  // Tab, Escape
            isSpecialKey = true
        case 0x73, 0x77, 0x74, 0x79, 0x72:  // Home, End, PageUp, PageDown, Insert
            isSpecialKey = true
        case 0x7A, 0x78, 0x63, 0x76, 0x60, 0x61,
             0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F:  // F1-F12
            isSpecialKey = true
        default:
            isSpecialKey = event.modifierFlags.contains(.control)
                || event.modifierFlags.contains(.command)
        }

        if isSpecialKey {
            let termEvent = convertKeyEvent(event)
            terminalDelegate?.terminalViewDidReceiveKeyEvent(termEvent)
        } else {
            // 通常の文字入力はIME経由（日本語入力対応）
            interpretKeyEvents([event])
        }
    }

    override func flagsChanged(with event: NSEvent) {
        // Handle modifier key changes if needed
    }

    private func convertKeyEvent(_ event: NSEvent) -> TerminalKeyEvent {
        var mods = TerminalKeyEvent.KeyModifiers()
        if event.modifierFlags.contains(.shift)   { mods.insert(.shift) }
        if event.modifierFlags.contains(.control)  { mods.insert(.control) }
        if event.modifierFlags.contains(.option)   { mods.insert(.alt) }
        if event.modifierFlags.contains(.command)  { mods.insert(.meta) }

        return TerminalKeyEvent(
            keyCode: event.keyCode,
            characters: event.characters ?? "",
            modifiers: mods,
            isKeyDown: event.type == .keyDown
        )
    }

    // MARK: - Mouse Event Handling

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pos = cellPosition(for: event)

        if event.clickCount == 2 {
            selectWord(at: pos)
            return
        }

        if event.clickCount == 3 {
            selectLine(at: pos)
            return
        }

        // Start selection or send mouse event
        let mods = mouseModifiers(event)
        if modes.isMouseTrackingActive && !event.modifierFlags.contains(.option) {
            terminalDelegate?.terminalViewDidReceiveMouseEvent(button: 0, x: pos.x, y: pos.y, isRelease: false, modifiers: mods)
        } else {
            // Start text selection
            isSelecting = true
            selectionStart = pos
            buffer?.selection = BufferSelection()
            buffer?.selection.startX = pos.x
            buffer?.selection.startY = pos.y
            buffer?.selection.endX = pos.x
            buffer?.selection.endY = pos.y
            buffer?.selection.isActive = true
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let pos = cellPosition(for: event)

        if isSelecting {
            buffer?.selection.endX = pos.x
            buffer?.selection.endY = pos.y
            needsDisplay = true
        } else if modes.isMouseTrackingActive && (modes.mouseTrackingButton || modes.mouseTrackingAny) {
            let mods = mouseModifiers(event)
            terminalDelegate?.terminalViewDidReceiveMouseEvent(button: 32, x: pos.x, y: pos.y, isRelease: false, modifiers: mods)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let pos = cellPosition(for: event)

        if isSelecting {
            isSelecting = false
            // Copy to clipboard if there's a selection
            if let text = buffer?.getSelectedText(), !text.isEmpty {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
            }
        } else if modes.isMouseTrackingActive {
            let mods = mouseModifiers(event)
            terminalDelegate?.terminalViewDidReceiveMouseEvent(button: 0, x: pos.x, y: pos.y, isRelease: true, modifiers: mods)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let pos = cellPosition(for: event)
        if modes.isMouseTrackingActive {
            let mods = mouseModifiers(event)
            terminalDelegate?.terminalViewDidReceiveMouseEvent(button: 2, x: pos.x, y: pos.y, isRelease: false, modifiers: mods)
        } else {
            // Show context menu with SF Symbols
            let menu = NSMenu()
            let copyItem = menu.addItem(withTitle: L("contextMenu.copy"), action: #selector(copyText(_:)), keyEquivalent: "c")
            let pasteItem = menu.addItem(withTitle: L("contextMenu.paste"), action: #selector(pasteText(_:)), keyEquivalent: "v")
            menu.addItem(NSMenuItem.separator())
            let selItem = menu.addItem(withTitle: L("contextMenu.selectAll"), action: #selector(selectAllText(_:)), keyEquivalent: "a")
            let clrItem = menu.addItem(withTitle: L("contextMenu.clearBuffer"), action: #selector(clearBuffer(_:)), keyEquivalent: "")
            if #available(macOS 11.0, *) {
                copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
                pasteItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
                selItem.image = NSImage(systemSymbolName: "selection.pin.in.out", accessibilityDescription: nil)
                clrItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        let pos = cellPosition(for: event)
        if modes.isMouseTrackingActive {
            let mods = mouseModifiers(event)
            terminalDelegate?.terminalViewDidReceiveMouseEvent(button: 2, x: pos.x, y: pos.y, isRelease: true, modifiers: mods)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let pos = cellPosition(for: event)
        let direction = event.scrollingDeltaY > 0 ? 1 : -1

        if modes.isMouseTrackingActive {
            let mods = mouseModifiers(event)
            terminalDelegate?.terminalViewDidReceiveScrollEvent(direction: direction, x: pos.x, y: pos.y, modifiers: mods)
        } else {
            // Scroll buffer
            if let buffer = buffer {
                let lines = Int(abs(event.scrollingDeltaY) / 3) + 1
                if direction > 0 {
                    buffer.scrollOffset = min(buffer.scrollOffset + lines, buffer.totalLines - buffer.height)
                } else {
                    buffer.scrollOffset = max(buffer.scrollOffset - lines, 0)
                }
                needsDisplay = true
            }
        }
    }

    // MARK: - Cell Position Helpers

    private func cellPosition(for event: NSEvent) -> (x: Int, y: Int) {
        let point = convert(event.locationInWindow, from: nil)
        let x = max(0, min(Int(point.x / cellWidth), columns - 1))
        let y = max(0, min(Int((point.y - topInset) / cellHeight), rows - 1))
        return (x, y)
    }

    private func mouseModifiers(_ event: NSEvent) -> TerminalKeyEvent.KeyModifiers {
        var mods = TerminalKeyEvent.KeyModifiers()
        if event.modifierFlags.contains(.shift) { mods.insert(.shift) }
        if event.modifierFlags.contains(.option) { mods.insert(.alt) }
        if event.modifierFlags.contains(.control) { mods.insert(.control) }
        return mods
    }

    // MARK: - Selection Helpers

    private func selectWord(at pos: (x: Int, y: Int)) {
        guard let buffer = buffer, let line = buffer.line(at: pos.y) else { return }

        // Find word boundaries
        var startX = pos.x
        var endX = pos.x

        let isWordChar: (Character) -> Bool = { c in
            return c.isLetter || c.isNumber || c == "_"
        }

        while startX > 0 && startX < line.cells.count && isWordChar(line.cells[startX].character) {
            startX -= 1
        }
        if startX < line.cells.count && !isWordChar(line.cells[startX].character) {
            startX += 1
        }

        while endX < line.cells.count - 1 && isWordChar(line.cells[endX].character) {
            endX += 1
        }

        buffer.selection.isActive = true
        buffer.selection.startX = startX
        buffer.selection.startY = pos.y
        buffer.selection.endX = endX
        buffer.selection.endY = pos.y
        needsDisplay = true
    }

    private func selectLine(at pos: (x: Int, y: Int)) {
        guard let buffer = buffer else { return }
        buffer.selection.isActive = true
        buffer.selection.startX = 0
        buffer.selection.startY = pos.y
        buffer.selection.endX = columns
        buffer.selection.endY = pos.y
        needsDisplay = true
    }

    // MARK: - Copy/Paste

    @objc func copyText(_ sender: Any?) {
        guard let text = buffer?.getSelectedText() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    @objc func pasteText(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        terminalDelegate?.terminalViewDidRequestPaste(text)
    }

    @objc func selectAllText(_ sender: Any?) {
        guard let buffer = buffer else { return }
        buffer.selection.isActive = true
        buffer.selection.startX = 0
        buffer.selection.startY = 0
        buffer.selection.endX = columns
        buffer.selection.endY = rows - 1
        needsDisplay = true
    }

    @objc func clearBuffer(_ sender: Any?) {
        buffer?.eraseInDisplay(3) // Clear scrollback
        buffer?.eraseInDisplay(2) // Clear screen
        needsDisplay = true
    }

    // MARK: - Focus

    override func becomeFirstResponder() -> Bool {
        terminalDelegate?.terminalViewDidGainFocus()
        cursorVisible = true
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        terminalDelegate?.terminalViewDidLoseFocus()
        needsDisplay = true
        return super.resignFirstResponder()
    }

    // MARK: - Refresh

    func refresh() {
        needsDisplay = true
    }
}

// MARK: - NSTextInputClient (IME Support)

extension TerminalView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let str = string as? String {
            text = str
        } else if let attrStr = string as? NSAttributedString {
            text = attrStr.string
        } else {
            return
        }

        markedText = nil
        imeMarkedRange = NSRange(location: NSNotFound, length: 0)

        // Send as key events
        for char in text {
            let event = TerminalKeyEvent(
                keyCode: 0,
                characters: String(char),
                modifiers: [],
                isKeyDown: true
            )
            terminalDelegate?.terminalViewDidReceiveKeyEvent(event)
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let str = string as? String {
            markedText = NSMutableAttributedString(string: str)
        } else if let attrStr = string as? NSAttributedString {
            markedText = NSMutableAttributedString(attributedString: attrStr)
        }
        imeMarkedRange = NSRange(location: 0, length: markedText?.length ?? 0)
        _selectedRange = selectedRange
        needsDisplay = true
    }

    func unmarkText() {
        markedText = nil
        imeMarkedRange = NSRange(location: NSNotFound, length: 0)
        needsDisplay = true
    }

    func selectedRange() -> NSRange {
        return _selectedRange
    }

    func markedRange() -> NSRange {
        return imeMarkedRange
    }

    func hasMarkedText() -> Bool {
        return markedText != nil && imeMarkedRange.location != NSNotFound
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        return nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return [.font, .foregroundColor, .underlineStyle]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let buffer = buffer else { return .zero }
        let x = CGFloat(buffer.cursorX) * cellWidth
        let y = topInset + CGFloat(buffer.cursorY) * cellHeight
        let screenRect = window?.convertToScreen(convert(CGRect(x: x, y: y, width: cellWidth, height: cellHeight), to: nil)) ?? .zero
        return screenRect
    }

    func characterIndex(for point: NSPoint) -> Int {
        return 0
    }
}
#endif
