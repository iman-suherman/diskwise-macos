#!/usr/bin/env bash
# Create a Sparkle-compatible ZIP archive from a signed DiskWise.app.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/.build/DerivedData/Build/Products/Release/DiskWise.app}"
VERSION="${2:-}"
OUTPUT_ZIP="${3:-}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  exit 1
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")"
fi

ZIP_NAME="DiskWise-${VERSION}.zip"
OUTPUT_ZIP="${OUTPUT_ZIP:-$ROOT_DIR/releases/sparkle/$ZIP_NAME}"

mkdir -p "$(dirname "$OUTPUT_ZIP")"
rm -f "$OUTPUT_ZIP"

echo "==> Creating Sparkle update archive"
echo "    App:    $APP_PATH"
echo "    Output: $OUTPUT_ZIP"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUTPUT_ZIP"
echo "Created: $OUTPUT_ZIP"
