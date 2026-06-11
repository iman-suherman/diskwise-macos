#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/DerivedData/Build/Products/Debug/DiskWise.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "==> DiskWise.app not found. Building debug app..."
  npm run build:app --prefix "$ROOT_DIR"
fi

echo "==> Launching DiskWise"
osascript -e 'tell application "DiskWise" to quit' >/dev/null 2>&1 || true
pkill -x DiskWise >/dev/null 2>&1 || true
sleep 0.5
open "$APP_PATH"
