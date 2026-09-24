#!/bin/zsh
set -euo pipefail

APP_NAME="TixcraftTime"
APP_DIR="$APP_NAME.app"
ICON_FILE="$APP_NAME-Round.icns"
ICON_SOURCE="assets/app-icon/$APP_NAME.icns"
ENTITLEMENTS="TixcraftTime.entitlements"
DEPLOYMENT_TARGET="12.0"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
CACHE_ROOT=".build/module-cache"
TASK_TMP_ROOT="${TMPDIR:-/tmp}"
STAGE_ROOT="$(mktemp -d "${TASK_TMP_ROOT%/}/tixcraft-time.XXXXXX")"
STAGE_APP="$STAGE_ROOT/$APP_NAME.app"

trap 'rm -rf "$STAGE_ROOT"' EXIT

[[ -f "$ICON_SOURCE" ]] || { print -u2 "Missing app icon: $ICON_SOURCE"; exit 1; }
[[ -f "$ENTITLEMENTS" ]] || { print -u2 "Missing entitlements: $ENTITLEMENTS"; exit 1; }

mkdir -p \
  "$STAGE_APP/Contents/MacOS" \
  "$STAGE_APP/Contents/Resources" \
  "$CACHE_ROOT"

for arch in arm64 x86_64; do
  mkdir -p "$CACHE_ROOT/$arch"
  swiftc TixcraftFloatingTime.swift \
    -warnings-as-errors \
    -target "${arch}-apple-macos${DEPLOYMENT_TARGET}" \
    -module-cache-path "$CACHE_ROOT/$arch" \
    -framework AppKit \
    -framework Carbon \
    -framework Foundation \
    -framework UserNotifications \
    -o "$STAGE_ROOT/TixcraftTime-$arch"
done

lipo -create \
  "$STAGE_ROOT/TixcraftTime-arm64" \
  "$STAGE_ROOT/TixcraftTime-x86_64" \
  -output "$STAGE_APP/Contents/MacOS/$APP_NAME"

cat > "$STAGE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Tixcraft Time</string>
  <key>CFBundleExecutable</key>
  <string>TixcraftTime</string>
  <key>CFBundleIconFile</key>
  <string>TixcraftTime-Round.icns</string>
  <key>CFBundleIdentifier</key>
  <string>io.github.stephenlin999.tixcraft-time</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Tixcraft Time</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.2.0</string>
  <key>CFBundleVersion</key>
  <string>3</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Stephen Lin. MIT License.</string>
</dict>
</plist>
PLIST

cp "$ICON_SOURCE" "$STAGE_APP/Contents/Resources/$ICON_FILE"
printf "APPL????" > "$STAGE_APP/Contents/PkgInfo"
chmod +x "$STAGE_APP/Contents/MacOS/$APP_NAME"

sign_args=(
  --force
  --options runtime
  --entitlements "$ENTITLEMENTS"
  --sign "$SIGN_IDENTITY"
)
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  sign_args+=(--timestamp=none)
else
  sign_args+=(--timestamp)
fi
codesign "${sign_args[@]}" "$STAGE_APP"

plutil -lint "$STAGE_APP/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$STAGE_APP"

rm -rf "$APP_DIR"
mv "$STAGE_APP" "$APP_DIR"
touch "$APP_DIR"
echo "Built $APP_DIR (Universal arm64+x86_64, macOS $DEPLOYMENT_TARGET+)"
