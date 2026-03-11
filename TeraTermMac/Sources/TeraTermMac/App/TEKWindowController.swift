/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Port of tekwin.cpp to Swift/macOS
 * TEK 4014 vector graphics emulation window
 */

#if canImport(AppKit)
import AppKit

// MARK: - TEK Window Controller (port of CTEKWindow)

/// Minimal TEK 4014 graphics terminal window.
/// The original Tera Term implements Tektronix 4014 vector graphics mode
/// where the host can send drawing commands (move, draw, point, text).
/// This window provides the container for that functionality.
class TEKWindowController: NSWindowController {

    private let settings: TerminalSettings
    private var tekView: TEKView!

    // MARK: - Initialization

    init(settings: TerminalSettings) {
        self.settings = settings

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tera Term: TEK"
        window.minSize = NSSize(width: 320, height: 240)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)

        super.init(window: window)

        setupTEKView()
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - View Setup

    private func setupTEKView() {
        guard let window = window else { return }

        tekView = TEKView(frame: window.contentView!.bounds)
        tekView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(tekView)
    }

    // MARK: - TEK Commands

    /// Process incoming TEK 4014 data from the terminal emulator.
    func processData(_ data: Data) {
        tekView.processData(data)
    }

    /// Clear the TEK graphics screen.
    func clearScreen() {
        tekView.clearScreen()
    }

    // MARK: - Printing (port of TEK window print functionality)

    /// Print the current TEK graphics content using macOS standard print dialog.
    func printTEKWindow() {
        guard let window = window else { return }

        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .fit
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true
        printInfo.orientation = tekView.bounds.width > tekView.bounds.height ? .landscape : .portrait

        let printOp = NSPrintOperation(view: tekView, printInfo: printInfo)
        printOp.showsPrintPanel = true
        printOp.showsProgressPanel = true
        printOp.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}

// MARK: - TEK View (port of teklib.c drawing surface)

/// NSView subclass that renders TEK 4014 vector graphics.
/// TEK 4014 uses a 4096x3120 addressable coordinate space.
class TEKView: NSView {

    // TEK 4014 coordinate space: 4096 x 3120
    private static let tekWidth: CGFloat = 4096
    private static let tekHeight: CGFloat = 3120

    // Drawing state
    private var drawCommands: [(type: DrawCommandType, points: [NSPoint], text: String?)] = []
    private var currentPosition: NSPoint = .zero

    override var isFlipped: Bool { true }

    enum DrawCommandType {
        case move
        case draw
        case point
        case text
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Black background
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)

        // Scale TEK coordinates to view bounds
        let scaleX = bounds.width / TEKView.tekWidth
        let scaleY = bounds.height / TEKView.tekHeight

        context.setStrokeColor(NSColor.green.cgColor)
        context.setFillColor(NSColor.green.cgColor)
        context.setLineWidth(1.0)

        for cmd in drawCommands {
            switch cmd.type {
            case .move:
                if let pt = cmd.points.first {
                    currentPosition = pt
                }
            case .draw:
                if let pt = cmd.points.first {
                    let from = NSPoint(x: currentPosition.x * scaleX, y: currentPosition.y * scaleY)
                    let to = NSPoint(x: pt.x * scaleX, y: pt.y * scaleY)
                    context.move(to: from)
                    context.addLine(to: to)
                    context.strokePath()
                    currentPosition = pt
                }
            case .point:
                if let pt = cmd.points.first {
                    let scaledPt = NSPoint(x: pt.x * scaleX, y: pt.y * scaleY)
                    context.fill(CGRect(x: scaledPt.x - 1, y: scaledPt.y - 1, width: 2, height: 2))
                    currentPosition = pt
                }
            case .text:
                if let text = cmd.text {
                    let scaledPt = NSPoint(x: currentPosition.x * scaleX, y: currentPosition.y * scaleY)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                        .foregroundColor: NSColor.green,
                    ]
                    (text as NSString).draw(at: scaledPt, withAttributes: attrs)
                }
            }
        }
    }

    // MARK: - Data Processing

    /// Process TEK 4014 data stream.
    /// This is a simplified parser; the original Tera Term handles the full
    /// TEK 4014 protocol including alpha mode, graph mode, GIN mode, etc.
    func processData(_ data: Data) {
        // Placeholder: actual TEK 4014 protocol parsing to be implemented
        needsDisplay = true
    }

    /// Clear all graphics and reset position.
    func clearScreen() {
        drawCommands.removeAll()
        currentPosition = .zero
        needsDisplay = true
    }
}

#endif
