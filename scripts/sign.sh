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

sign_binary() {
  local target="$1"
  local entitlements="${2:-}"
  if [[ -n "$entitlements" ]]; then
    codesign \
      --force \
      --options runtime \
      --entitlements "$entitlements" \
      --sign "$IDENTITY" \
      --timestamp \
      "$target"
  else
    codesign \
      --force \
      --options runtime \
      --sign "$IDENTITY" \
      --timestamp \
      "$target"
  fi
}

sign_sparkle_framework() {
  local sparkle_root="$APP_PATH/Contents/Frameworks/Sparkle.framework"
  [[ -d "$sparkle_root" ]] || return 0

  echo "    Signing Sparkle.framework embedded helpers"

  while IFS= read -r xpc; do
    [[ -z "$xpc" ]] && continue
    sign_binary "$xpc"
  done < <(find "$sparkle_root" -name "*.xpc" -type d | sort -r)

  while IFS= read -r helper; do
    [[ -z "$helper" ]] && continue
    sign_binary "$helper"
  done < <(find "$sparkle_root" -name "*.app" -type d | sort -r)

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    sign_binary "$file"
  done < <(find "$sparkle_root" \( -name "*.dylib" -o -perm -111 \) -type f | sort -r)

  sign_binary "$sparkle_root"
}

while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  if [[ "$file" == *".app/Contents/MacOS/"* ]]; then
    continue
  fi
  if [[ "$file" == *"Sparkle.framework"* ]]; then
    continue
  fi
  sign_binary "$file" 2>/dev/null || true
done < <(find "$APP_PATH" \( -name "*.dylib" -o -name "*.node" -o -perm -111 \) -type f)

while IFS= read -r helper; do
  [[ -z "$helper" ]] && continue
  [[ "$helper" == "$APP_PATH" ]] && continue
  if [[ "$helper" == *"Sparkle.framework"* ]]; then
    continue
  fi
  sign_binary "$helper" 2>/dev/null || true
done < <(find "$APP_PATH" -name "*.app")

while IFS= read -r xpc; do
  [[ -z "$xpc" ]] && continue
  if [[ "$xpc" == *"Sparkle.framework"* ]]; then
    continue
  fi
  sign_binary "$xpc" 2>/dev/null || true
done < <(find "$APP_PATH" -name "*.xpc")

sign_sparkle_framework
sign_binary "$APP_PATH" "$ENTITLEMENTS"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "Signed successfully."
