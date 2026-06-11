#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/release-env.sh"

APP_PATH="${1:-$ROOT_DIR/.build/DerivedData/Build/Products/Release/DiskWise.app}"
OUTPUT_DMG="${2:-$ROOT_DIR/DiskWise.dmg}"
IDENTITY="${DEVELOPER_ID_APPLICATION:-$MACOS_CODESIGN_IDENTITY}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  exit 1
fi

echo "==> Creating DMG"
bash "$ROOT_DIR/scripts/create-dmg.sh" "$APP_PATH" "$OUTPUT_DMG"

echo "==> Signing DMG"
codesign --force --sign "$IDENTITY" --timestamp "$OUTPUT_DMG"

if should_notarize; then
  append_notary_auth_args
  if [[ ${#NOTARY_AUTH_ARGS[@]} -eq 0 ]]; then
    echo "Notarization enabled but credentials missing."
    echo "Set APPLE_NOTARIZE_KEYCHAIN_PROFILE=AC_NOTARY or APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD + APPLE_TEAM_ID"
    exit 1
  fi

  echo "==> Submitting DMG for notarization"
  SUBMIT_JSON="$(mktemp)"
  xcrun notarytool submit "$OUTPUT_DMG" "${NOTARY_AUTH_ARGS[@]}" --output-format json >"$SUBMIT_JSON"
  SUBMISSION_ID="$(python3 -c "import json; print(json.load(open('$SUBMIT_JSON')).get('id',''))")"
  rm -f "$SUBMIT_JSON"

  if [[ -z "$SUBMISSION_ID" ]]; then
    echo "Notary submission did not return a submission id."
    exit 1
  fi

  echo "    Submission ID: $SUBMISSION_ID"
  echo "==> Waiting for Apple notarization (usually 5–15 minutes)"
  xcrun notarytool wait "$SUBMISSION_ID" "${NOTARY_AUTH_ARGS[@]}" --timeout 1h --progress || true

  STATUS="$(xcrun notarytool info "$SUBMISSION_ID" "${NOTARY_AUTH_ARGS[@]}" --output-format json | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))")"
  if [[ "$STATUS" != "Accepted" ]]; then
    echo "Notarization failed with status: ${STATUS:-unknown}"
    xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_AUTH_ARGS[@]}" || true
    exit 1
  fi

  echo "==> Stapling notarization ticket to DMG"
  xcrun stapler staple "$OUTPUT_DMG"
  xcrun stapler validate "$OUTPUT_DMG"
  echo "Notarized and stapled."
else
  echo "Notarization skipped (set MACOS_NOTARIZE=1 and configure AC_NOTARY profile)."
fi

echo "Created: $OUTPUT_DMG"
