#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"

./build_app.sh

open "TixcraftTime.app"
