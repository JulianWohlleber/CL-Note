#!/usr/bin/env bash
# Build Note_.app
set -euo pipefail

APP="Note_.app"
BUNDLE="$APP/Contents"

echo "▸ Compiling…"
swift build -c release 2>&1

ARCH=$(uname -m)
BUILD_DIR=".build/${ARCH}-apple-macosx/release"
BINARY="$BUILD_DIR/Note_"
RESOURCE_BUNDLE="$BUILD_DIR/Note__Note_.bundle"

[ -f "$BINARY" ] || { echo "✗ Build failed — binary not found"; exit 1; }

echo "▸ Packaging $APP…"
rm -rf "$APP"
mkdir -p "$BUNDLE/MacOS" "$BUNDLE/Resources"

cp "$BINARY" "$BUNDLE/MacOS/Note_"

# Copy resource bundle (fonts etc.) next to the app bundle root
# Bundle.main.bundleURL resolves to Note_.app/ so the bundle goes there
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -r "$RESOURCE_BUNDLE" "$APP/Note__Note_.bundle"
fi

# Copy app icon
ICON_SRC="Sources/Note_/Resources/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$BUNDLE/Resources/AppIcon.icns"
fi

cat > "$BUNDLE/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>             <string>Note_</string>
  <key>CFBundleDisplayName</key>      <string>Note_</string>
  <key>CFBundleIdentifier</key>       <string>com.julianwohlleber.note_</string>
  <key>CFBundleVersion</key>          <string>1.0.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key>       <string>Note_</string>
  <key>CFBundlePackageType</key>      <string>APPL</string>
  <key>NSPrincipalClass</key>         <string>NSApplication</string>
  <key>CFBundleIconFile</key>          <string>AppIcon</string>
  <key>NSHighResolutionCapable</key>  <true/>
  <key>LSMinimumSystemVersion</key>   <string>13.0</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc codesign so Gatekeeper lets it run
echo "▸ Codesigning…"
codesign --force --deep --sign - "$APP" 2>/dev/null || true
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "✓ Done → $APP"
echo "  To install: cp -r $APP /Applications/"
echo "  To run now: open $APP"
