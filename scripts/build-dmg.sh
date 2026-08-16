#!/bin/bash
# build-dmg.sh — Builds Spotdraw.app bundle and packages as DMG
set -e

VERSION="1.0.0"
APP_NAME="Spotdraw"
BUNDLE_ID="com.spotdraw.app"

echo "🔨 Building release binary..."
swift build -c release

echo "📦 Creating app bundle..."
APP_DIR="dist/${APP_NAME}.app"
rm -rf dist
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy binary
cp .build/release/Spotdraw "${APP_DIR}/Contents/MacOS/Spotdraw"

# Create Info.plist
cat > "${APP_DIR}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Spotdraw. MIT License.</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# Create PkgInfo
echo -n "APPL????" > "${APP_DIR}/Contents/PkgInfo"

echo "✅ App bundle created at dist/${APP_NAME}.app"

# Create DMG
echo "💿 Creating DMG..."
DMG_NAME="${APP_NAME}-${VERSION}"
DMG_PATH="dist/${DMG_NAME}.dmg"
TEMP_DMG="dist/temp.dmg"

# Create temporary DMG
hdiutil create -size 10m -fs HFS+ -volname "${APP_NAME}" "${TEMP_DMG}" -quiet

# Mount it
MOUNT_DIR=$(hdiutil attach "${TEMP_DMG}" -readwrite | grep "Apple_HFS" | sed 's/.*Apple_HFS[[:space:]]*//')

# Copy app
cp -R "${APP_DIR}" "${MOUNT_DIR}/"

# Create Applications symlink
ln -s /Applications "${MOUNT_DIR}/Applications"

# Unmount
hdiutil detach "${MOUNT_DIR}" -force 2>/dev/null || true

# Convert to compressed DMG
hdiutil convert "${TEMP_DMG}" -format UDZO -o "${DMG_PATH}" -quiet
rm "${TEMP_DMG}"

echo "✅ DMG created at ${DMG_PATH}"
echo ""
echo "📏 Sizes:"
echo "   Binary: $(du -h .build/release/Spotdraw | awk '{print $1}')"
echo "   App:    $(du -sh dist/${APP_NAME}.app | awk '{print $1}')"
echo "   DMG:    $(du -h dist/${DMG_NAME}.dmg | awk '{print $1}')"
echo ""
echo "🚀 To install:"
echo "   1. Open ${DMG_NAME}.dmg"
echo "   2. Drag Spotdraw to Applications"
echo "   3. Right-click → Open (first time only, since app is unsigned)"
