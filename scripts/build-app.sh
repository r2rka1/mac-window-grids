#!/bin/bash
# Builds build/WindowGrids.app. Pass --install to copy it to /Applications and launch it.
#
# Signing: macOS ties the Accessibility grant to the code signature. With a real
# signing identity the grant survives rebuilds; with ad-hoc signing it has to be
# granted again after every build. Set SIGN_IDENTITY to choose one, or "-" for ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/WindowGrids"
APP="build/WindowGrids.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN" "$APP/Contents/MacOS/WindowGrids"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null |
    awk -F'"' '/Developer ID Application|Apple Development/ {print $2; exit}')}"
if [[ -n "$IDENTITY" && "$IDENTITY" != "-" ]] &&
    perl -e 'alarm 60; exec @ARGV' codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null; then
    echo "signed with a keychain identity"
else
    codesign --force --sign - "$APP"
    echo "signed ad-hoc (Accessibility access must be re-granted after each build)"
fi
echo "built $APP"

if [[ "${1:-}" == "--install" ]]; then
    DEST="/Applications/WindowGrids.app"
    pkill -x WindowGrids 2>/dev/null || true
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "installed and launched $DEST"
fi
