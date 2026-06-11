#!/usr/bin/env bash
# Load release signing env (Huge Shop defaults match officeless-ai-vscode-guardrail-kit).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$ROOT_DIR/.env.release" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env.release"
  set +a
fi

if [[ -f "$ROOT_DIR/.env.release" ]] || [[ "${DISKWISE_RELEASE_DEFAULTS:-0}" == "1" ]]; then
  export MACOS_CODESIGN_IDENTITY="${MACOS_CODESIGN_IDENTITY:-Developer ID Application: Huge Shop Pty Ltd (Q3TXW887NM)}"
  export DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-$MACOS_CODESIGN_IDENTITY}"
  export APPLE_TEAM_ID="${APPLE_TEAM_ID:-Q3TXW887NM}"
  export APPLE_ID="${APPLE_ID:-support@hugeshop.com}"
  export MACOS_NOTARIZE="${MACOS_NOTARIZE:-1}"
  export APPLE_NOTARIZE_KEYCHAIN_PROFILE="${APPLE_NOTARIZE_KEYCHAIN_PROFILE:-AC_NOTARY}"
fi

export APPLE_ID_PASSWORD="${APPLE_ID_PASSWORD:-${APPLE_APP_SPECIFIC_PASSWORD:-}}"

notary_profile_exists() {
  local profile="${1:-$APPLE_NOTARIZE_KEYCHAIN_PROFILE}"
  [[ -n "$profile" ]] && xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1
}

notary_credentials_configured() {
  if [[ -n "${APPLE_NOTARIZE_KEYCHAIN_PROFILE:-}" ]]; then
    if notary_profile_exists; then
      return 0
    fi
    echo "release: notary profile '${APPLE_NOTARIZE_KEYCHAIN_PROFILE}' is not in the Keychain — skipping notarization." >&2
    return 1
  fi
  [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]
}

should_notarize() {
  [[ "${MACOS_NOTARIZE:-0}" == "1" ]] && notary_credentials_configured
}

append_notary_auth_args() {
  NOTARY_AUTH_ARGS=()
  if [[ -n "${APPLE_NOTARIZE_KEYCHAIN_PROFILE:-}" ]]; then
    NOTARY_AUTH_ARGS=(--keychain-profile "$APPLE_NOTARIZE_KEYCHAIN_PROFILE")
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
    NOTARY_AUTH_ARGS=(
      --apple-id "$APPLE_ID"
      --password "$APPLE_APP_SPECIFIC_PASSWORD"
      --team-id "$APPLE_TEAM_ID"
    )
  fi
}
