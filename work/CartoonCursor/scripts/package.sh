#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKSPACE_DIR="$(cd "$ROOT_DIR/../.." && pwd)"
OUTPUT_DIR="$WORKSPACE_DIR/outputs"
APP_NAME="CartoonCursor"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"

cd "$ROOT_DIR"
mkdir -p ".build/release"
clang -fobjc-arc -O2 \
    -arch arm64 \
    -arch x86_64 \
    -mmacosx-version-min=13.0 \
    "Sources/CartoonCursor/main.m" \
    -framework ApplicationServices \
    -framework Cocoa \
    -framework CoreGraphics \
    -framework UniformTypeIdentifiers \
    -o ".build/release/$APP_NAME"

rm -rf "$APP_DIR" "$OUTPUT_DIR/$APP_NAME.zip"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>local.codex.cartooncursor</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Cartoon Cursor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.16</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Cartoon Cursor needs Accessibility permission to replace the visible mouse cursor with your selected sticker.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

cd "$OUTPUT_DIR"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$APP_NAME.zip"

echo "$APP_DIR"
