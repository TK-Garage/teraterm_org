/*
 * Copyright (C) 1994-1998 T. Teranishi
 * (C) 2004- TeraTerm Project
 * All rights reserved.
 *
 * Ported to Swift/macOS
 *
 * NSView extension for generating debug PNG snapshots of dialog layouts.
 * Renders the view offscreen with a red boundary overlay to verify that
 * controls fit within the specified frame.
 */

#if canImport(AppKit)
import AppKit

extension NSView {

    /// Render this view to a PNG file on the Desktop under `TT_UI_Preview/`.
    ///
    /// - Parameter name: A short identifier used in the filename,
    ///   e.g. `"01_NewConnection"`.  The resulting file will be named
    ///   `<name>_<yyyyMMdd>.png`.
    ///
    /// The method forces a full Auto Layout pass, draws a 2pt red border
    /// around the view bounds, then uses `cacheDisplay(in:to:)` for
    /// offscreen rendering — no window needs to be on-screen.
    func saveToDebugPNG(name: String) {
        // 1. Force layout to settle
        layoutSubtreeIfNeeded()

        let bounds = self.bounds
        guard bounds.width > 0 && bounds.height > 0 else {
            NSLog("[DebugSnapshot] View has zero size – skipping \(name)")
            return
        }

        // 2. Render into a bitmap
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width),
            pixelsHigh: Int(bounds.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            NSLog("[DebugSnapshot] Failed to create bitmap for \(name)")
            return
        }

        cacheDisplay(in: bounds, to: bitmapRep)

        // 3. Draw 2pt red boundary overlay
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep) {
            NSGraphicsContext.current = ctx
            NSColor.red.setStroke()
            let borderPath = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            borderPath.lineWidth = 2
            borderPath.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()

        // 4. Build output path: ~/Desktop/TT_UI_Preview/<name>_<date>.png
        let dateStr = {
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd"
            return df.string(from: Date())
        }()

        let desktopURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("TT_UI_Preview")

        do {
            try FileManager.default.createDirectory(
                at: desktopURL, withIntermediateDirectories: true)
        } catch {
            NSLog("[DebugSnapshot] Cannot create directory: \(error)")
            return
        }

        let fileURL = desktopURL
            .appendingPathComponent("\(name)_\(dateStr).png")

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            NSLog("[DebugSnapshot] PNG encoding failed for \(name)")
            return
        }

        do {
            try pngData.write(to: fileURL, options: .atomic)
            NSLog("[DebugSnapshot] Saved: \(fileURL.path)")
        } catch {
            NSLog("[DebugSnapshot] Write failed: \(error)")
        }
    }
}
#endif
