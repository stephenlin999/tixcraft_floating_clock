#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

if [[ ! -x "TixcraftTime.app/Contents/MacOS/TixcraftTime" ]]; then
  ./build_app.sh
fi

open "TixcraftTime.app"
