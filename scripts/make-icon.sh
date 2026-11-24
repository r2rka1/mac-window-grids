#!/bin/bash
# Regenerates Resources/AppIcon.icns and docs/icon.png from the pixel art in Mascot.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/WindowGrids"
mkdir -p build docs
"$BIN" --icon build/icon-1024.png

SET=build/AppIcon.iconset
rm -rf "$SET" && mkdir -p "$SET"
for s in 16 32 128 256 512; do
    sips -z $s $s build/icon-1024.png --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
sips -z 256 256 build/icon-1024.png --out docs/icon.png >/dev/null
echo "wrote Resources/AppIcon.icns and docs/icon.png"
