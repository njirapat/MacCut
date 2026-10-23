#!/bin/bash
# Build MacCut.app (universal: Apple Silicon + Intel) into ./build. Needs Xcode Command Line Tools only.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/MacCut.app
SOURCES=(MacCut.swift HelpView.swift)
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swift make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos14.0" -o "build/MacCut-$arch" "${SOURCES[@]}"
done
lipo -create build/MacCut-arm64 build/MacCut-x86_64 -output "$APP/Contents/MacOS/MacCut"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
