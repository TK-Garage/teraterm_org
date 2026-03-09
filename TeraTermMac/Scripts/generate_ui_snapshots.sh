#!/bin/bash
# generate_ui_snapshots.sh
#
# Xcode Run Script Phase — generates PNG snapshots of each dialog layout.
#
# Usage (Xcode Build Phase → Run Script):
#   ${SRCROOT}/Scripts/generate_ui_snapshots.sh
#
# Or standalone:
#   cd TeraTermMac && ./Scripts/generate_ui_snapshots.sh [--open]
#
# Options:
#   --open   Open the output folder in Finder after generation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SRCROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
OUTPUT_DIR="$HOME/Desktop/TT_UI_Preview"

echo "[UISnapshot] Project: $PROJECT_DIR"
echo "[UISnapshot] Output:  $OUTPUT_DIR"

# Build the snapshot runner as a small command-line tool.
# It links AppKit and invokes SnapshotGenerator.generateAll().
RUNNER_SRC="$PROJECT_DIR/Scripts/_snapshot_runner.swift"
RUNNER_BIN="${DERIVED_FILE_DIR:-/tmp}/_tt_snapshot_runner"

# Create the ephemeral runner source
cat > "$RUNNER_SRC" << 'SWIFT_EOF'
import AppKit

// Ensure NSApplication is initialized (needed for offscreen AppKit rendering)
let _ = NSApplication.shared

// Import is implicit since we compile all sources together; but for a
// standalone script we call the generator via a small trampoline that
// the build system links against the main target's object files.
//
// When used as a Run Script phase the simplest approach is to invoke
// the built product with a special argument.
//
// This file is compiled standalone, so we replicate the call here:
SnapshotGenerator.generateAll()
exit(0)
SWIFT_EOF

echo "[UISnapshot] Compiling snapshot runner..."

# Collect all Swift sources from the Settings directory (contains
# SnapshotGenerator, DialogConstants, TerminalSetupViewController, etc.)
SETTINGS_DIR="$PROJECT_DIR/Sources/TeraTermMac/Settings"
APP_DIR="$PROJECT_DIR/Sources/TeraTermMac/App"

SWIFT_SOURCES=(
    "$SETTINGS_DIR/DialogConstants.swift"
    "$SETTINGS_DIR/TerminalSettings.swift"
    "$SETTINGS_DIR/TerminalSetupViewController.swift"
    "$SETTINGS_DIR/NSView+DebugSnapshot.swift"
    "$SETTINGS_DIR/SnapshotGenerator.swift"
    "$RUNNER_SRC"
)

# Find additional model files that define types used by the dialogs
for f in "$PROJECT_DIR/Sources/TeraTermMac"/**/*.swift; do
    # Skip already-included files and test files
    case "$f" in
        */Tests/*|*/_snapshot_runner.swift) continue ;;
    esac
done

# Try to compile.  If it fails (missing types from other modules),
# fall back to invoking the main executable with --generate-snapshots.
if swiftc \
    -O \
    -framework AppKit \
    -framework CoreText \
    -framework IOKit \
    -framework Security \
    -import-objc-header /dev/null \
    -module-name TTSnapshot \
    -o "$RUNNER_BIN" \
    "${SWIFT_SOURCES[@]}" 2>/dev/null; then

    echo "[UISnapshot] Running snapshot generator..."
    "$RUNNER_BIN"
else
    echo "[UISnapshot] Standalone compile failed; using built product fallback."
    # Fallback: run the main app binary with a snapshot flag.
    # The app can check for this argument in applicationDidFinishLaunching.
    BUILT_PRODUCT="${BUILT_PRODUCTS_DIR:-$PROJECT_DIR/.build/debug}/TeraTermMac"
    if [ -x "$BUILT_PRODUCT" ]; then
        "$BUILT_PRODUCT" --generate-snapshots &
        SNAPSHOT_PID=$!
        # Give it a few seconds to render, then kill
        sleep 3
        kill "$SNAPSHOT_PID" 2>/dev/null || true
    else
        echo "[UISnapshot] WARNING: No built product found. Build the project first."
    fi
fi

# Cleanup
rm -f "$RUNNER_SRC"

# Report
if [ -d "$OUTPUT_DIR" ]; then
    echo "[UISnapshot] Generated files:"
    ls -la "$OUTPUT_DIR"/*.png 2>/dev/null || echo "  (no PNG files found)"
else
    echo "[UISnapshot] WARNING: Output directory not created."
fi

# --open flag: reveal in Finder
if [[ "${1:-}" == "--open" ]] && [ -d "$OUTPUT_DIR" ]; then
    open "$OUTPUT_DIR"
fi

echo "[UISnapshot] Done."
