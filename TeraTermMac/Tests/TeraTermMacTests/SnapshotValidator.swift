/*
 * SnapshotValidator.swift
 * Pixel-level snapshot comparison for Tera Term UI components.
 *
 * Architecture:
 *   1. Render an NSView or NSWindow into an NSBitmapImageRep
 *   2. Compare against a reference PNG stored in the test bundle
 *   3. Report differences with a tolerance threshold
 *   4. Optionally generate a diff image highlighting changed pixels
 *
 * Reference images are stored at:
 *   Tests/TeraTermMacTests/Resources/Snapshots/<identifier>.png
 *
 * When a reference image does not exist, the validator creates it
 * (record mode) and the test passes. On subsequent runs, it compares.
 *
 * Coordinate Drift Detection:
 *   The validator can check that a specific control is located at
 *   an expected (x, y) position within its parent, detecting layout
 *   regressions where Auto Layout constraints shift components.
 */

import XCTest
@testable import TeraTermMac

#if canImport(AppKit)
import AppKit

// MARK: - Snapshot Result

struct SnapshotComparisonResult {
    let matched: Bool
    let totalPixels: Int
    let differentPixels: Int
    let differencePercentage: Double
    let diffImagePath: String?

    var summary: String {
        if matched {
            return "Snapshot matches reference"
        }
        return String(format: "%.2f%% pixels differ (%d of %d)",
                      differencePercentage * 100, differentPixels, totalPixels)
    }
}

// MARK: - Coordinate Check Result

struct CoordinateCheckResult {
    let controlIdentifier: String
    let expectedOrigin: NSPoint
    let actualOrigin: NSPoint
    let expectedSize: NSSize?
    let actualSize: NSSize
    let positionDrift: NSPoint     // (dx, dy) from expected

    var withinTolerance: Bool {
        return abs(positionDrift.x) <= CoordinateCheckResult.tolerance
            && abs(positionDrift.y) <= CoordinateCheckResult.tolerance
    }

    /// Maximum acceptable drift in points (accounts for retina rounding)
    static let tolerance: CGFloat = 2.0

    var summary: String {
        if withinTolerance {
            return "\(controlIdentifier): position OK (drift: \(positionDrift.x), \(positionDrift.y))"
        }
        return "\(controlIdentifier): DRIFTED by (\(positionDrift.x), \(positionDrift.y)) " +
               "expected=(\(expectedOrigin.x),\(expectedOrigin.y)) " +
               "actual=(\(actualOrigin.x),\(actualOrigin.y))"
    }
}

// MARK: - Snapshot Validator

class SnapshotValidator {

    /// Directory where reference snapshots are stored.
    let referenceDirectory: URL

    /// Directory where diff images are written on failure.
    let outputDirectory: URL

    /// Pixel difference tolerance (0.0 = exact match, 1.0 = completely different).
    /// Values below this threshold are considered matching.
    var toleranceThreshold: Double = 0.005  // 0.5% default

    /// Whether to record new snapshots when no reference exists.
    var recordMode: Bool = true

    init(referenceDirectory: URL? = nil, outputDirectory: URL? = nil) {
        let testBundle = Bundle(for: type(of: self) as! AnyClass.Type)
        self.referenceDirectory = referenceDirectory
            ?? testBundle.resourceURL?.appendingPathComponent("Snapshots")
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("TeraTermSnapshots/Reference")
        self.outputDirectory = outputDirectory
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("TeraTermSnapshots/Output")

        // Ensure directories exist
        try? FileManager.default.createDirectory(at: self.referenceDirectory,
                                                  withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: self.outputDirectory,
                                                  withIntermediateDirectories: true)
    }

    // MARK: - View Rendering

    /// Render an NSView to an NSBitmapImageRep.
    /// The view must have a valid frame (non-zero size).
    static func renderView(_ view: NSView) -> NSBitmapImageRep? {
        let bounds = view.bounds
        guard bounds.width > 0 && bounds.height > 0 else { return nil }

        // Force layout pass
        view.layoutSubtreeIfNeeded()

        guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        view.cacheDisplay(in: bounds, to: bitmapRep)
        return bitmapRep
    }

    /// Render an NSWindow's content view.
    static func renderWindow(_ window: NSWindow) -> NSBitmapImageRep? {
        guard let contentView = window.contentView else { return nil }
        return renderView(contentView)
    }

    // MARK: - Save / Load PNG

    /// Save a bitmap representation as PNG to the given URL.
    static func savePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw SnapshotError.pngEncodingFailed
        }
        try pngData.write(to: url)
    }

    /// Load a PNG file as NSBitmapImageRep.
    static func loadPNG(from url: URL) -> NSBitmapImageRep? {
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data),
              let rep = image.representations.first as? NSBitmapImageRep else {
            // Try alternative loading
            guard let data = try? Data(contentsOf: url) else { return nil }
            return NSBitmapImageRep(data: data)
        }
        return rep
    }

    // MARK: - Comparison

    /// Compare a rendered view against its reference snapshot.
    /// Returns the comparison result.
    func validateView(
        _ view: NSView,
        identifier: String,
        file: StaticString = #file,
        line: UInt = #line
    ) -> SnapshotComparisonResult {
        guard let rendered = Self.renderView(view) else {
            return SnapshotComparisonResult(
                matched: false, totalPixels: 0, differentPixels: 0,
                differencePercentage: 1.0, diffImagePath: nil)
        }

        let refURL = referenceDirectory.appendingPathComponent("\(identifier).png")

        // Check if reference exists
        if !FileManager.default.fileExists(atPath: refURL.path) {
            if recordMode {
                try? Self.savePNG(rendered, to: refURL)
                return SnapshotComparisonResult(
                    matched: true, totalPixels: Int(rendered.pixelsWide * rendered.pixelsHigh),
                    differentPixels: 0, differencePercentage: 0.0,
                    diffImagePath: nil)
            } else {
                return SnapshotComparisonResult(
                    matched: false, totalPixels: 0, differentPixels: 0,
                    differencePercentage: 1.0, diffImagePath: nil)
            }
        }

        // Load reference
        guard let reference = Self.loadPNG(from: refURL) else {
            return SnapshotComparisonResult(
                matched: false, totalPixels: 0, differentPixels: 0,
                differencePercentage: 1.0, diffImagePath: nil)
        }

        return compareImages(rendered: rendered, reference: reference, identifier: identifier)
    }

    /// Pixel-by-pixel comparison of two bitmap representations.
    func compareImages(
        rendered: NSBitmapImageRep,
        reference: NSBitmapImageRep,
        identifier: String
    ) -> SnapshotComparisonResult {
        let width = min(rendered.pixelsWide, reference.pixelsWide)
        let height = min(rendered.pixelsHigh, reference.pixelsHigh)
        let totalPixels = width * height

        guard totalPixels > 0 else {
            return SnapshotComparisonResult(
                matched: false, totalPixels: 0, differentPixels: 0,
                differencePercentage: 1.0, diffImagePath: nil)
        }

        // Size mismatch is a failure
        let sizeMismatch = rendered.pixelsWide != reference.pixelsWide
                        || rendered.pixelsHigh != reference.pixelsHigh

        var differentPixels = 0

        // Create diff image
        let diffRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )

        for y in 0..<height {
            for x in 0..<width {
                let renderedColor = rendered.colorAt(x: x, y: y)
                let referenceColor = reference.colorAt(x: x, y: y)

                if let rc = renderedColor, let refC = referenceColor {
                    let rDiff = abs(rc.redComponent - refC.redComponent)
                    let gDiff = abs(rc.greenComponent - refC.greenComponent)
                    let bDiff = abs(rc.blueComponent - refC.blueComponent)
                    let maxDiff = max(rDiff, max(gDiff, bDiff))

                    if maxDiff > 0.01 { // Per-pixel tolerance
                        differentPixels += 1
                        // Mark diff pixel in red
                        diffRep?.setColor(.red, atX: x, y: y)
                    } else {
                        // Matching pixel — show dimmed
                        diffRep?.setColor(
                            NSColor(white: rc.brightnessComponent * 0.3, alpha: 1.0),
                            atX: x, y: y)
                    }
                } else {
                    differentPixels += 1
                    diffRep?.setColor(.magenta, atX: x, y: y)
                }
            }
        }

        let percentage = Double(differentPixels) / Double(totalPixels)
        let matched = !sizeMismatch && percentage <= toleranceThreshold

        // Save diff image if there are differences
        var diffPath: String? = nil
        if !matched, let diffRep = diffRep {
            let diffURL = outputDirectory.appendingPathComponent("\(identifier)_diff.png")
            try? Self.savePNG(diffRep, to: diffURL)
            diffPath = diffURL.path

            // Also save the actual rendering for comparison
            let actualURL = outputDirectory.appendingPathComponent("\(identifier)_actual.png")
            try? Self.savePNG(rendered, to: actualURL)
        }

        return SnapshotComparisonResult(
            matched: matched,
            totalPixels: totalPixels,
            differentPixels: differentPixels,
            differencePercentage: percentage,
            diffImagePath: diffPath
        )
    }

    // MARK: - Coordinate Checking

    /// Verify that a control is at its expected position within a parent view.
    static func checkControlPosition(
        view: NSView,
        identifier: String,
        expectedOrigin: NSPoint,
        expectedSize: NSSize? = nil
    ) -> CoordinateCheckResult {
        let control = findControl(in: view, identifier: identifier)
        let actualOrigin: NSPoint
        let actualSize: NSSize

        if let control = control {
            // Get position relative to the root view
            let converted = control.convert(control.bounds.origin, to: view)
            actualOrigin = converted
            actualSize = control.frame.size
        } else {
            actualOrigin = NSPoint(x: -1, y: -1)
            actualSize = .zero
        }

        let drift = NSPoint(
            x: actualOrigin.x - expectedOrigin.x,
            y: actualOrigin.y - expectedOrigin.y
        )

        return CoordinateCheckResult(
            controlIdentifier: identifier,
            expectedOrigin: expectedOrigin,
            actualOrigin: actualOrigin,
            expectedSize: expectedSize,
            actualSize: actualSize,
            positionDrift: drift
        )
    }

    /// Recursively find a control by accessibilityIdentifier.
    private static func findControl(in view: NSView, identifier: String) -> NSView? {
        if view.accessibilityIdentifier() == identifier {
            return view
        }
        for subview in view.subviews {
            if let found = findControl(in: subview, identifier: identifier) {
                return found
            }
        }
        return nil
    }

    /// Batch check multiple controls' positions.
    static func checkAllControlPositions(
        in view: NSView,
        expected: [(identifier: String, origin: NSPoint, size: NSSize?)]
    ) -> [CoordinateCheckResult] {
        return expected.map { spec in
            checkControlPosition(
                view: view,
                identifier: spec.identifier,
                expectedOrigin: spec.origin,
                expectedSize: spec.size
            )
        }
    }
}

// MARK: - Errors

enum SnapshotError: LocalizedError {
    case pngEncodingFailed
    case referenceNotFound(String)
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .pngEncodingFailed: return "Failed to encode bitmap as PNG"
        case .referenceNotFound(let id): return "Reference snapshot not found: \(id)"
        case .renderFailed: return "Failed to render view to bitmap"
        }
    }
}

// MARK: - XCTest Integration Extension

extension XCTestCase {

    /// Assert that a view matches its reference snapshot.
    func assertSnapshot(
        _ view: NSView,
        identifier: String,
        tolerance: Double = 0.005,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let validator = SnapshotValidator()
        validator.toleranceThreshold = tolerance
        let result = validator.validateView(view, identifier: identifier, file: file, line: line)

        if !result.matched {
            XCTFail(
                "Snapshot mismatch for '\(identifier)': \(result.summary)" +
                (result.diffImagePath.map { "\nDiff saved to: \($0)" } ?? ""),
                file: file, line: line
            )
        }
    }

    /// Assert that controls are within tolerance of expected positions.
    func assertControlPositions(
        in view: NSView,
        expected: [(identifier: String, origin: NSPoint, size: NSSize?)],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let results = SnapshotValidator.checkAllControlPositions(in: view, expected: expected)
        for result in results {
            if !result.withinTolerance {
                XCTFail(result.summary, file: file, line: line)
            }
        }
    }
}

// MARK: - Snapshot Validator Tests

final class SnapshotValidatorTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapTest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    func testRenderSimpleView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 50))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.red.cgColor

        let rep = SnapshotValidator.renderView(view)
        XCTAssertNotNil(rep, "Should render a simple view")
        XCTAssertGreaterThan(rep?.pixelsWide ?? 0, 0)
        XCTAssertGreaterThan(rep?.pixelsHigh ?? 0, 0)
    }

    func testSaveAndLoadPNG() throws {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.blue.cgColor

        guard let rep = SnapshotValidator.renderView(view) else {
            XCTFail("Render failed")
            return
        }

        let url = tmpDir.appendingPathComponent("test.png")
        try SnapshotValidator.savePNG(rep, to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let loaded = SnapshotValidator.loadPNG(from: url)
        XCTAssertNotNil(loaded, "Should load saved PNG")
        XCTAssertEqual(loaded?.pixelsWide, rep.pixelsWide)
        XCTAssertEqual(loaded?.pixelsHigh, rep.pixelsHigh)
    }

    func testIdenticalImagesMatch() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.green.cgColor

        guard let rep = SnapshotValidator.renderView(view) else {
            XCTFail("Render failed")
            return
        }

        let validator = SnapshotValidator(
            referenceDirectory: tmpDir,
            outputDirectory: tmpDir.appendingPathComponent("output")
        )
        let result = validator.compareImages(rendered: rep, reference: rep, identifier: "identical")

        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.differentPixels, 0)
        XCTAssertEqual(result.differencePercentage, 0.0)
    }

    func testDifferentImagesDoNotMatch() {
        let view1 = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view1.wantsLayer = true
        view1.layer?.backgroundColor = NSColor.red.cgColor

        let view2 = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view2.wantsLayer = true
        view2.layer?.backgroundColor = NSColor.blue.cgColor

        guard let rep1 = SnapshotValidator.renderView(view1),
              let rep2 = SnapshotValidator.renderView(view2) else {
            XCTFail("Render failed")
            return
        }

        let outDir = tmpDir.appendingPathComponent("output")
        let validator = SnapshotValidator(
            referenceDirectory: tmpDir,
            outputDirectory: outDir
        )
        let result = validator.compareImages(rendered: rep1, reference: rep2, identifier: "different")

        XCTAssertFalse(result.matched)
        XCTAssertGreaterThan(result.differentPixels, 0)
        XCTAssertGreaterThan(result.differencePercentage, 0.0)
    }

    func testRecordModeCreatesReference() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.yellow.cgColor

        let refDir = tmpDir.appendingPathComponent("refs")
        let validator = SnapshotValidator(
            referenceDirectory: refDir,
            outputDirectory: tmpDir.appendingPathComponent("output")
        )
        validator.recordMode = true

        let result = validator.validateView(view, identifier: "newSnapshot")

        XCTAssertTrue(result.matched, "Record mode should pass")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: refDir.appendingPathComponent("newSnapshot.png").path),
            "Reference file should be created")
    }

    func testCoordinateCheckWithinTolerance() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let child = NSView(frame: NSRect(x: 100, y: 50, width: 80, height: 24))
        child.setAccessibilityIdentifier("test.control")
        parent.addSubview(child)

        let result = SnapshotValidator.checkControlPosition(
            view: parent,
            identifier: "test.control",
            expectedOrigin: NSPoint(x: 100, y: 50)
        )

        XCTAssertTrue(result.withinTolerance,
            "Control at exact expected position should be within tolerance")
        XCTAssertEqual(result.positionDrift.x, 0)
        XCTAssertEqual(result.positionDrift.y, 0)
    }

    func testCoordinateCheckDrift() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let child = NSView(frame: NSRect(x: 110, y: 55, width: 80, height: 24))
        child.setAccessibilityIdentifier("drifted.control")
        parent.addSubview(child)

        let result = SnapshotValidator.checkControlPosition(
            view: parent,
            identifier: "drifted.control",
            expectedOrigin: NSPoint(x: 100, y: 50)
        )

        XCTAssertEqual(result.positionDrift.x, 10.0)
        XCTAssertEqual(result.positionDrift.y, 5.0)
        XCTAssertFalse(result.withinTolerance,
            "10pt drift should exceed tolerance")
    }

    func testCoordinateCheckMissingControl() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        let result = SnapshotValidator.checkControlPosition(
            view: parent,
            identifier: "nonexistent",
            expectedOrigin: NSPoint(x: 100, y: 50)
        )

        XCTAssertFalse(result.withinTolerance)
    }

    func testBatchCoordinateCheck() {
        let parent = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        let c1 = NSView(frame: NSRect(x: 20, y: 30, width: 60, height: 20))
        c1.setAccessibilityIdentifier("control.a")
        parent.addSubview(c1)

        let c2 = NSView(frame: NSRect(x: 200, y: 30, width: 60, height: 20))
        c2.setAccessibilityIdentifier("control.b")
        parent.addSubview(c2)

        let results = SnapshotValidator.checkAllControlPositions(in: parent, expected: [
            (identifier: "control.a", origin: NSPoint(x: 20, y: 30), size: nil),
            (identifier: "control.b", origin: NSPoint(x: 200, y: 30), size: nil),
        ])

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].withinTolerance)
        XCTAssertTrue(results[1].withinTolerance)
    }

    func testZeroSizeViewReturnsNil() {
        let view = NSView(frame: .zero)
        let rep = SnapshotValidator.renderView(view)
        XCTAssertNil(rep, "Zero-size view should not render")
    }
}

// MARK: - Settings Dialog Snapshot Tests

/// Snapshot tests for all implemented settings dialogs.
/// On first run (record mode), reference images are created.
/// On subsequent runs, the test compares against the reference.
final class SettingsDialogSnapshotTests: XCTestCase {

    func testTerminalSetupSnapshot() {
        let settings = TerminalSettings()
        let vc = TerminalSetupViewController(settings: settings)
        vc.loadView()
        vc.viewDidLoad()
        assertSnapshot(vc.view, identifier: "TerminalSetup")
    }

    func testWindowSetupSnapshot() {
        let settings = TerminalSettings()
        let vc = WindowSetupViewController(settings: settings)
        vc.loadView()
        vc.viewDidLoad()
        assertSnapshot(vc.view, identifier: "WindowSetup")
    }

    func testSerialPortSetupSnapshot() {
        let settings = TerminalSettings()
        let vc = SerialPortSetupViewController(settings: settings)
        vc.loadView()
        vc.viewDidLoad()
        assertSnapshot(vc.view, identifier: "SerialPortSetup")
    }

    func testSSHAuthSnapshot() {
        let settings = TerminalSettings()
        let vc = SSHAuthViewController(settings: settings)
        vc.loadView()
        vc.viewDidLoad()
        assertSnapshot(vc.view, identifier: "SSHAuth")
    }
}

#endif
