#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/release-env.sh"

APP_PATH="${1:-$ROOT_DIR/.build/DerivedData/Build/Products/Release/DiskWise.app}"
IDENTITY="${DEVELOPER_ID_APPLICATION:-$MACOS_CODESIGN_IDENTITY}"
ENTITLEMENTS="$ROOT_DIR/app/DiskWise/entitlements.mac.plist"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  echo "Run npm run build:app:release first."
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "Entitlements not found: $ENTITLEMENTS"
  exit 1
fi

echo "==> Signing $APP_PATH"
echo "    Identity: $IDENTITY"

sign_file() {
  local target="$1"
  codesign \
    --force \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" \
    --timestamp \
    "$target"
}

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  if [[ "$file" == *".app/Contents/MacOS/"* ]]; then
    continue
  fi
  sign_file "$file" 2>/dev/null || true
done < <(find "$APP_PATH" \( -name "*.dylib" -o -name "*.node" -o -perm -111 \) -type f)

while IFS= read -r helper; do
  [[ -z "$helper" ]] && continue
  sign_file "$helper" 2>/dev/null || true
done < <(find "$APP_PATH" -name "*.app" -path "*/Helpers/*")

sign_file "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "Signed successfully."
