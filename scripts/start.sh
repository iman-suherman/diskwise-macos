#!/usr/bin/env bash
# Build a release DiskWise.app, sign it locally, and create a drag-and-drop DMG.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/DerivedData/Build/Products/Release/DiskWise.app"
OUTPUT_DMG="$ROOT_DIR/DiskWise.dmg"

echo "==> Building DiskWise release app"
bash "$ROOT_DIR/scripts/build.sh" release

if [[ ! -d "$APP_PATH" ]]; then
  echo "Release build failed — DiskWise.app not found at:"
  echo "$APP_PATH"
  exit 1
fi

if [[ -f "$ROOT_DIR/.env.release" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/scripts/release-env.sh"
  echo "==> Signing with Developer ID (.env.release)"
  bash "$ROOT_DIR/scripts/sign.sh" "$APP_PATH"
else
  echo "==> Ad-hoc signing for local install"
  echo "    For distribution signing, copy .env.release.example to .env.release"
  codesign --force --deep --sign - "$APP_PATH"
  codesign --verify --verbose "$APP_PATH"
fi

echo "==> Creating DMG installer"
bash "$ROOT_DIR/scripts/create-dmg.sh" "$APP_PATH" "$OUTPUT_DMG"

if [[ "${SPARKLE_LOCAL:-1}" == "1" ]]; then
  echo "==> Publishing Sparkle artifacts for local website"
  node "$ROOT_DIR/scripts/sparkle-local-publish.cjs"
fi

echo ""
echo "Done."
echo "  DMG: $OUTPUT_DMG"
echo "  Open the disk image, drag DiskWise.app to Applications, then launch from /Applications."
echo ""

open "$OUTPUT_DMG"
