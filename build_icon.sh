#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/tixcraft-icon.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
swift -module-cache-path "$STAGE/module-cache" render_icon.swift \
  assets/app-icon/source-minimal-ticket-clock-light.png "$STAGE/centered.png"
SOURCE="$STAGE/centered.png"
ICONSET="$STAGE/TixcraftTime.iconset"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
  for scale in 1 2; do
    suffix=""
    [[ "$scale" == 2 ]] && suffix="@2x"
    pixels=$((size * scale))
    sips -z "$pixels" "$pixels" "$SOURCE" \
      --out "$ICONSET/icon_${size}x${size}${suffix}.png" >/dev/null
  done
done

iconutil -c icns "$ICONSET" -o "$STAGE/TixcraftTime.icns"
iconutil -c iconset "$STAGE/TixcraftTime.icns" -o "$STAGE/verified.iconset"
cp "$STAGE/TixcraftTime.icns" assets/app-icon/TixcraftTime.icns
cp "$SOURCE" assets/app-icon/source-minimal-ticket-clock-light-rounded.png
echo "Built TixcraftTime.icns with macOS iconutil"
