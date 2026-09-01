#!/bin/bash
# Builds OtterLocal in release mode and packages it into a proper
# OtterLocal.app bundle. This matters because macOS ties permissions (like
# microphone access) and Dock/app identity to a real .app bundle with an
# Info.plist -- a bare command-line binary doesn't behave the same way.
set -euo pipefail

cd "$(dirname "$0")"

echo "Building OtterLocal (release)..."
swift build -c release

APP_NAME="OtterLocal"
APP_DIR="$APP_NAME.app"
BIN_PATH=".build/release/$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "AppIcon/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>OtterLocal</string>
    <key>CFBundleIdentifier</key>
    <string>com.otterlocal.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>OtterLocal needs microphone access to record and transcribe your lectures.</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
</dict>
</plist>
PLIST

SIGNING_IDENTITY="OtterLocal Local Signing"

echo "Signing (with $SIGNING_IDENTITY)..."
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"

echo ""
echo "Done. Launch with:"
echo "  open $APP_DIR"
