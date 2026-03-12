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

    /// Render this view to a PNG file.
    ///
    /// - Parameters:
    ///   - name: A short identifier used in the filename,
    ///     e.g. `"01_NewConnection"`.  The resulting file will be named
    ///     `<name>_<yyyyMMdd>.png`.
    ///   - outputDir: Optional output directory URL.  When `nil` (default),
    ///     falls back to the project `img/` directory (detected via Bundle)
    ///     or `~/Desktop/TT_UI_Preview/`.
    ///
    /// The method forces a full Auto Layout pass, draws a 2pt red border
    /// around the view bounds, then uses `cacheDisplay(in:to:)` for
    /// offscreen rendering — no window needs to be on-screen.
    func saveToDebugPNG(name: String, outputDir: URL? = nil) {
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

        // 3. Draw 2pt red boundary overlay + optional sub-control borders
        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep) {
            NSGraphicsContext.current = ctx

            // Outer red border
            NSColor.red.setStroke()
            let borderPath = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            borderPath.lineWidth = 2
            borderPath.stroke()

            // Draw sub-control boundaries for debugging
            drawSubviewBorders(in: self, rootView: self, ctx: ctx)
        }
        NSGraphicsContext.restoreGraphicsState()

        // 4. Build output path
        let dateStr = {
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd"
            return df.string(from: Date())
        }()

        let desktopURL: URL
        if let dir = outputDir {
            desktopURL = dir
        } else {
            // Try TeraTermMac/img/ directory first
            let bundlePath = Bundle.main.bundlePath
            let projectImg = URL(fileURLWithPath: bundlePath)
                .deletingLastPathComponent()  // .build/debug
                .deletingLastPathComponent()  // .build
                .deletingLastPathComponent()  // TeraTermMac
                .appendingPathComponent("img")
            if FileManager.default.isWritableFile(atPath: projectImg.deletingLastPathComponent().path) {
                desktopURL = projectImg
            } else {
                desktopURL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop")
                    .appendingPathComponent("TT_UI_Preview")
            }
        }

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

    /// Recursively draw thin borders around each direct subview.
    /// Uses alternating blue/green colours so nested levels are distinct.
    private func drawSubviewBorders(in view: NSView, rootView: NSView, ctx: NSGraphicsContext, depth: Int = 0) {
        let colors: [NSColor] = [
            NSColor.blue.withAlphaComponent(0.4),
            NSColor.green.withAlphaComponent(0.4),
            NSColor.orange.withAlphaComponent(0.4),
            NSColor.purple.withAlphaComponent(0.4),
        ]
        let color = colors[depth % colors.count]

        for sub in view.subviews {
            let rect = sub.convert(sub.bounds, to: rootView)
            guard rect.width > 0 && rect.height > 0 else { continue }

            color.setStroke()
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 0.5
            path.stroke()

            // Recurse into children (limit depth to avoid noise)
            if depth < 3 {
                drawSubviewBorders(in: sub, rootView: rootView, ctx: ctx, depth: depth + 1)
            }
        }
    }

    /// Capture the view as a PNG to a specific file path.
    /// Useful in automated tests where the output location is known.
    func captureScreenToPNG(fileName: String, directory: URL? = nil) {
        let dir = directory ?? FileManager.default.temporaryDirectory
        saveToDebugPNG(name: fileName, outputDir: dir)
    }
}
#endif
