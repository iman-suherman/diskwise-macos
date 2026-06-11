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

bash "$ROOT_DIR/scripts/build.sh" release
bash "$ROOT_DIR/scripts/sign.sh"
bash "$ROOT_DIR/scripts/package.sh"

echo ""
echo "Release complete: $ROOT_DIR/DiskWise.dmg"
echo "Drag DiskWise.app to Applications — Gatekeeper should accept the notarized build."
