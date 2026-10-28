#!/bin/bash
# Build SwiftNX and assemble a double-clickable SwiftNX.app in dist/.
#
# Usage:
#   ./Scripts/build-app.sh              # release build
#   ./Scripts/build-app.sh --debug      # debug build
#
# The script works with Xcode selected as well as with only the Command Line
# Tools. In the latter case it loads the SwiftUI macro plugin from /Applications
# /Xcode.app, which the CLT SDK does not ship on recent macOS versions.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then
    CONFIG="debug"
fi

XCODE_APP="/Applications/Xcode.app"
if [[ -n "${DEVELOPER_DIR:-}" && -d "$DEVELOPER_DIR/../.." ]]; then
    XCODE_APP="$(cd "$DEVELOPER_DIR/../.." && pwd)"
fi
PLUGIN="$XCODE_APP/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib"
DEVELOPER_DIR_PATH="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
SWIFT_ARGS=()
if [[ "$DEVELOPER_DIR_PATH" == *CommandLineTools* && -f "$PLUGIN" ]]; then
    # The CLT SDK declares SwiftUI's @State macro but ships no macro plugin.
    # Recent Xcode installations do, so load it explicitly for this build.
    SWIFT_ARGS=(-Xswiftc -load-plugin-library -Xswiftc "$PLUGIN")
fi

build() {
    swift build -c "$CONFIG" "$@"
}

echo "▸ Building SwiftNX ($CONFIG)…"
if [[ ${#SWIFT_ARGS[@]} -gt 0 ]]; then
    if ! build "${SWIFT_ARGS[@]}"; then
        echo "error: build failed." >&2
        exit 1
    fi
elif ! build; then
    if [[ -f "$PLUGIN" ]]; then
        echo "▸ Retrying with Xcode's SwiftUI macro plugin…"
        if ! build -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN"; then
            echo "error: build failed." >&2
            exit 1
        fi
    else
        echo "error: build failed." >&2
        exit 1
    fi
fi

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
EXECUTABLE="$BIN_DIR/SwiftNX"
if [[ ! -x "$EXECUTABLE" ]]; then
    echo "error: executable not found at $EXECUTABLE" >&2
    exit 1
fi

if [[ ! -f "Resources/AppIcon.icns" ]]; then
    echo "▸ Rendering the app icon…"
    swift Scripts/make-icon.swift Resources
fi

APP="$ROOT/dist/SwiftNX.app"
echo "▸ Assembling $APP…"
/bin/rm -rf "$APP"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

/bin/cp "$EXECUTABLE" "$APP/Contents/MacOS/SwiftNX"
/bin/cp Resources/Info.plist "$APP/Contents/Info.plist"
/bin/cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
/bin/chmod +x "$APP/Contents/MacOS/SwiftNX"

/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null
/usr/bin/codesign --force --sign - "$APP" >/dev/null

echo "▸ Signed ad-hoc."
echo "✓ $APP"
echo
echo "Open it with:"
echo "  open \"$APP\""
