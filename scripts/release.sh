#!/usr/bin/env bash
# Signed + notarized release (Huge Shop Developer ID, same as officeless-ai-vscode-guardrail-kit).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DISKWISE_RELEASE_DEFAULTS=1
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/release-env.sh"

echo "==> DiskWise release"
echo "    Identity: ${DEVELOPER_ID_APPLICATION:-$MACOS_CODESIGN_IDENTITY}"
echo "    Team ID:  ${APPLE_TEAM_ID}"
echo "    Notarize: ${MACOS_NOTARIZE} (profile: ${APPLE_NOTARIZE_KEYCHAIN_PROFILE:-none})"
echo ""

OUTPUT_DMG="${OUTPUT_DMG:-$ROOT_DIR/DiskWise.dmg}"
mkdir -p "$(dirname "$OUTPUT_DMG")"

bash "$ROOT_DIR/scripts/build.sh" release
bash "$ROOT_DIR/scripts/sign.sh"
bash "$ROOT_DIR/scripts/package.sh" "" "$OUTPUT_DMG"

if [[ "${SPARKLE_LOCAL:-1}" == "1" ]]; then
  echo ""
  echo "==> Publishing Sparkle artifacts for local website"
  node "$ROOT_DIR/scripts/sparkle-local-publish.cjs"
fi

echo ""
echo "Release complete: $OUTPUT_DMG"
echo "Drag DiskWise.app to Applications — Gatekeeper should accept the notarized build."
if [[ "${SPARKLE_LOCAL:-1}" == "1" ]]; then
  echo "Local Sparkle feed: run npm run dev:website then test updates from http://127.0.0.1:3000/appcast.xml"
fi
