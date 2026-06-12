#!/usr/bin/env bash
# Create a drag-and-drop DMG from DiskWise.app.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/.build/DerivedData/Build/Products/Release/DiskWise.app}"
OUTPUT_DMG="${2:-$ROOT_DIR/DiskWise.dmg}"
VOLUME_NAME="${3:-DiskWise}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  exit 1
fi

APP_NAME="$(basename "$APP_PATH")"
ICON_PATH="$ROOT_DIR/app/DiskWise/Assets/AppIcon.icns"

rm -f "$OUTPUT_DMG"

if command -v create-dmg >/dev/null 2>&1; then
  echo "==> Creating DMG with create-dmg"
  CREATE_DMG_ARGS=(
    --volname "$VOLUME_NAME"
    --window-pos 200 120
    --window-size 660 400
    --icon-size 128
    --icon "$APP_NAME" 180 185
    --hide-extension "$APP_NAME"
    --app-drop-link 480 185
  )
  if [[ -f "$ICON_PATH" ]]; then
    CREATE_DMG_ARGS=(--volicon "$ICON_PATH" "${CREATE_DMG_ARGS[@]}")
  fi
  create-dmg "${CREATE_DMG_ARGS[@]}" "$OUTPUT_DMG" "$APP_PATH"
  bash "$ROOT_DIR/scripts/configure-dmg-statusbar.sh" "$OUTPUT_DMG" "$VOLUME_NAME" || {
    echo "Warning: DMG status bar configuration skipped"
  } || {
    echo "Warning: DMG status bar configuration skipped"
  }
else
  echo "==> Creating DMG with hdiutil (install create-dmg for a richer layout: brew install create-dmg)"
  STAGING_DIR="$(mktemp -d)"
  trap 'rm -rf "$STAGING_DIR"' EXIT
  cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME"
  ln -s /Applications "$STAGING_DIR/Applications"
  hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT_DMG" >/dev/null
  bash "$ROOT_DIR/scripts/configure-dmg-statusbar.sh" "$OUTPUT_DMG" "$VOLUME_NAME" || {
    echo "Warning: DMG status bar configuration skipped"
  }
fi

echo "Created: $OUTPUT_DMG"
