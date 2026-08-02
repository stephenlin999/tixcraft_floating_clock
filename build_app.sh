#!/bin/zsh
set -euo pipefail

APP_NAME="TixcraftTime"
APP_DIR="$APP_NAME.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
CACHE_DIR=".build/module-cache"
ICON_FILE="$APP_NAME.icns"
ICON_SOURCE="assets/app-icon/$ICON_FILE"

mkdir -p "$BIN_DIR" "$RES_DIR" "$CACHE_DIR"

swiftc TixcraftFloatingTime.swift \
  -module-cache-path "$CACHE_DIR" \
  -framework AppKit \
  -framework Foundation \
  -o "$BIN_DIR/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>TixcraftTime</string>
  <key>CFBundleIdentifier</key>
  <string>local.tixcraft-time.floating</string>
  <key>CFBundleName</key>
  <string>Tixcraft Time</string>
  <key>CFBundleIconFile</key>
  <string>TixcraftTime.icns</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$RES_DIR/$ICON_FILE"
fi

printf "APPL????" > "$APP_DIR/Contents/PkgInfo"
chmod +x "$BIN_DIR/$APP_NAME"
codesign --force --deep --sign - "$APP_DIR"
touch "$APP_DIR"
echo "Built $APP_DIR"
