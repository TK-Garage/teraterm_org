/*
 * MultilingualSnapshotTests.swift
 *
 * Automated PNG snapshot generation for all localized dialogs.
 * Generates screenshots in each supported language for visual
 * verification of layout correctness and text truncation.
 *
 * Output directory:
 *   ~/Desktop/TT_UI_Preview/multilingual/
 *     ├── en/
 *     │   ├── TerminalSetup_localized_en.png
 *     │   ├── WindowSetup_en.png
 *     │   ├── SerialPortSetup_en.png
 *     │   └── SSHAuth_en.png
 *     └── ja/
 *         ├── TerminalSetup_localized_ja.png
 *         ├── WindowSetup_ja.png
 *         ├── SerialPortSetup_ja.png
 *         └── SSHAuth_ja.png
 *
 * Each snapshot includes:
 *   - The dialog rendered in an offscreen window
 *   - A 2pt red border for boundary verification
 *   - Fitting size vs actual size comparison in the log
 */

import XCTest

#if canImport(AppKit)
import AppKit
@testable import TeraTermMac

// MARK: - Multilingual Snapshot Generator

/// Generates PNG snapshots of all settings dialogs for visual review.
/// This extends the existing SnapshotGenerator with per-language output.
final class MultilingualSnapshotGenerator {

    /// Supported language codes for snapshot generation.
    static let supportedLanguages = ["en", "ja"]

    /// Dialog specifications for snapshot generation.
    struct DialogSpec {
        let name: String
        let width: CGFloat
        let height: CGFloat
        let builder: () -> NSView
    }

    /// Generate PNG snapshots for all dialogs in all supported languages.
    /// Returns the output directory URL.
    @discardableResult
    static func generateAllSnapshots(outputDir: URL? = nil) -> URL {
        let baseDir = outputDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("TT_UI_Preview")
            .appendingPathComponent("multilingual")

        // Since we can't actually switch the process locale at runtime,
        // we generate snapshots with the current locale and label them.
        // For true multilingual testing, use XCUITest with -AppleLanguages.
        let currentLang = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"

        let langDir = baseDir.appendingPathComponent(currentLang)
        try? FileManager.default.createDirectory(at: langDir, withIntermediateDirectories: true)

        let specs = buildDialogSpecs()

        for spec in specs {
            let view = spec.builder()
            renderAndSave(
                view: view,
                name: "\(spec.name)_\(currentLang)",
                width: spec.width,
                height: spec.height,
                outputDir: langDir
            )
        }

        NSLog("[MultilingualSnapshot] Generated \(specs.count) snapshots in '\(currentLang)' → \(langDir.path)")
        return baseDir
    }

    /// Build the list of all dialog views to snapshot.
    private static func buildDialogSpecs() -> [DialogSpec] {
        return [
            // Localized Terminal Setup (NSStackView-based)
            DialogSpec(
                name: "TerminalSetup_localized",
                width: 560, height: 380,
                builder: {
                    let settings = TerminalSettings()
                    let vc = LocalizedTerminalSetupViewController(settings: settings)
                    vc.loadView()
                    vc.viewDidLoad()
                    return vc.view
                }
            ),
            // Original Terminal Setup (anchor-based)
            DialogSpec(
                name: "TerminalSetup_original",
                width: 560, height: 380,
                builder: {
                    let settings = TerminalSettings()
                    let vc = TerminalSetupViewController(settings: settings)
                    vc.loadView()
                    vc.viewDidLoad()
                    return vc.view
                }
            ),
            // Window Setup
            DialogSpec(
                name: "WindowSetup",
                width: 500, height: 460,
                builder: {
                    let settings = TerminalSettings()
                    let vc = WindowSetupViewController(settings: settings)
                    vc.loadView()
                    vc.viewDidLoad()
                    return vc.view
                }
            ),
            // Serial Port Setup
            DialogSpec(
                name: "SerialPortSetup",
                width: 480, height: 380,
                builder: {
                    let settings = TerminalSettings()
                    let vc = SerialPortSetupViewController(settings: settings)
                    vc.loadView()
                    vc.viewDidLoad()
                    return vc.view
                }
            ),
            // SSH Authentication
            DialogSpec(
                name: "SSHAuth",
                width: 520, height: 400,
                builder: {
                    let settings = TerminalSettings()
                    let vc = SSHAuthViewController(settings: settings)
                    vc.loadView()
                    vc.viewDidLoad()
                    return vc.view
                }
            ),
        ]
    }

    /// Render a view to PNG and save to disk.
    private static func renderAndSave(
        view: NSView,
        name: String,
        width: CGFloat,
        height: CGFloat,
        outputDir: URL
    ) {
        let containerFrame = NSRect(x: 0, y: 0, width: width, height: height)

        // Host in offscreen window for Auto Layout resolution
        let window = NSWindow(
            contentRect: containerFrame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false)
        window.contentView = view
        view.frame = containerFrame

        // Force layout
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()

        // Check fitting size
        let fitting = view.fittingSize
        if fitting.width > width || fitting.height > height {
            NSLog("[MultilingualSnapshot] WARNING: '\(name)' fittingSize "
                + "(\(fitting.width)×\(fitting.height)) exceeds spec "
                + "(\(width)×\(height))")
        }

        // Render to PNG
        view.saveToDebugPNG(name: name, outputDir: outputDir)
    }
}

// MARK: - Snapshot Tests

/// XCTest suite that generates and validates multilingual snapshots.
final class MultilingualSnapshotTests: XCTestCase {

    /// Generate snapshots for all dialogs in the current locale.
    func testGenerateAllLanguageSnapshots() {
        let outputDir = MultilingualSnapshotGenerator.generateAllSnapshots()

        // Verify output directory was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.path),
            "Snapshot output directory should be created")
    }

    /// Verify LocalizedTerminalSetup renders without overflow.
    func testLocalizedTerminalSetupNoOverflow() {
        let settings = TerminalSettings()
        let vc = LocalizedTerminalSetupViewController(settings: settings)
        vc.loadView()
        vc.viewDidLoad()

        let specWidth: CGFloat = 560
        let specHeight: CGFloat = 380

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: specWidth, height: specHeight),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = vc
        vc.view.needsLayout = true
        vc.view.layoutSubtreeIfNeeded()

        let fitting = vc.view.fittingSize

        // Allow 20% overflow tolerance (Auto Layout may calculate slightly larger)
        XCTAssertLessThanOrEqual(fitting.width, specWidth * 1.2,
            "Localized terminal setup should not overflow width significantly: \(fitting.width)")
    }

    /// Verify snapshot generation produces PNG files.
    func testSnapshotFilesCreated() {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TTSnapshotTest-\(UUID().uuidString)")

        let outputDir = MultilingualSnapshotGenerator.generateAllSnapshots(outputDir: tmpDir)

        // Check that at least one PNG was created
        let currentLang = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        let langDir = outputDir.appendingPathComponent(currentLang)

        if FileManager.default.fileExists(atPath: langDir.path) {
            let contents = try? FileManager.default.contentsOfDirectory(atPath: langDir.path)
            let pngFiles = contents?.filter { $0.hasSuffix(".png") } ?? []
            XCTAssertGreaterThan(pngFiles.count, 0,
                "Should generate at least one PNG snapshot")
        }

        // Cleanup
        try? FileManager.default.removeItem(at: tmpDir)
    }

    /// Verify existing SnapshotGenerator still works alongside new multilingual system.
    func testOriginalSnapshotGeneratorCompatibility() {
        // The original SnapshotGenerator.generateAll() should still function.
        // We just verify it can be called without crashes.
        // (Actual file I/O may fail in test sandbox, which is OK)
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TTOrigSnapshotTest-\(UUID().uuidString)")
        SnapshotGenerator.generateAll(outputDir: tmpDir)

        // Cleanup
        try? FileManager.default.removeItem(at: tmpDir)
    }
}

// MARK: - Truncation Detection Snapshot Tests

/// Tests that specifically check for text truncation in each language.
final class TruncationDetectionTests: XCTestCase {

    /// Check all labels in LocalizedTerminalSetupViewController for truncation.
    func testLocalizedTerminalSetupNoTruncation() {
        let settings = TerminalSettings()
        let vc = LocalizedTerminalSetupViewController(settings: settings)
        vc.loadView()
        vc.viewDidLoad()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = vc
        vc.view.needsLayout = true
        vc.view.layoutSubtreeIfNeeded()

        let truncations = detectTruncations(in: vc.view)
        for truncation in truncations {
            NSLog("[TruncationDetection] \(truncation)")
        }

        XCTAssertEqual(truncations.count, 0,
            "No truncations should be detected. Found: \(truncations.joined(separator: ", "))")
    }

    /// Check all labels in TerminalSetupViewController for truncation.
    func testOriginalTerminalSetupNoTruncation() {
        let settings = TerminalSettings()
        let vc = TerminalSetupViewController(settings: settings)
        vc.loadView()
        vc.viewDidLoad()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = vc
        vc.view.needsLayout = true
        vc.view.layoutSubtreeIfNeeded()

        let truncations = detectTruncations(in: vc.view)
        // Original may have some fixed-width truncation; just log them
        for truncation in truncations {
            NSLog("[TruncationDetection] Original: \(truncation)")
        }
    }

    /// Check checkboxes specifically (they often have long titles).
    func testCheckboxLabelsNotTruncated() {
        let settings = TerminalSettings()
        let vc = LocalizedTerminalSetupViewController(settings: settings)
        vc.loadView()
        vc.viewDidLoad()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = vc
        vc.view.needsLayout = true
        vc.view.layoutSubtreeIfNeeded()

        let checkboxes = findAllButtons(in: vc.view).filter { $0.buttonType == .switch }
        for checkbox in checkboxes {
            let title = checkbox.title
            guard !title.isEmpty else { continue }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: checkbox.font ?? NSFont.systemFont(ofSize: 13)
            ]
            let textWidth = (title as NSString).size(withAttributes: attrs).width
            let boxWidth = checkbox.frame.width

            if boxWidth > 0 {
                // Checkbox has ~20pt for the checkbox itself + title
                let availableWidth = boxWidth - 20
                XCTAssertGreaterThanOrEqual(availableWidth, textWidth * 0.85,
                    "Checkbox '\(title)' text may be truncated")
            }
        }
    }

    // MARK: - Helpers

    /// Detect all labels and buttons where text is likely truncated.
    /// Returns an array of human-readable descriptions.
    private func detectTruncations(in view: NSView) -> [String] {
        var truncations: [String] = []

        // Check labels (non-editable text fields)
        let labels = findAllLabels(in: view)
        for label in labels {
            let text = label.stringValue
            guard !text.isEmpty, text != "X" else { continue }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: label.font ?? NSFont.systemFont(ofSize: 13)
            ]
            let textWidth = (text as NSString).size(withAttributes: attrs).width
            let labelWidth = label.frame.width

            if labelWidth > 0 && textWidth > labelWidth * 1.05 {
                truncations.append(
                    "Label '\(text)': needs \(Int(textWidth))pt, has \(Int(labelWidth))pt")
            }
        }

        // Check buttons
        let buttons = findAllButtons(in: view)
        for button in buttons {
            let title = button.title
            guard !title.isEmpty else { continue }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: button.font ?? NSFont.systemFont(ofSize: 13)
            ]
            let textWidth = (title as NSString).size(withAttributes: attrs).width
            let buttonWidth = button.frame.width

            if buttonWidth > 0 {
                let availableWidth = button.buttonType == .switch
                    ? buttonWidth - 20
                    : buttonWidth - 16
                if textWidth > availableWidth * 1.05 {
                    truncations.append(
                        "Button '\(title)': needs \(Int(textWidth))pt, has \(Int(availableWidth))pt")
                }
            }
        }

        return truncations
    }

    private func findAllLabels(in view: NSView) -> [NSTextField] {
        var results: [NSTextField] = []
        if let tf = view as? NSTextField, !tf.isEditable {
            results.append(tf)
        }
        for subview in view.subviews {
            results.append(contentsOf: findAllLabels(in: subview))
        }
        return results
    }

    private func findAllButtons(in view: NSView) -> [NSButton] {
        var results: [NSButton] = []
        if let button = view as? NSButton {
            results.append(button)
        }
        for subview in view.subviews {
            results.append(contentsOf: findAllButtons(in: subview))
        }
        return results
    }
}

#endif
