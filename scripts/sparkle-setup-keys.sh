#!/usr/bin/env bash
# Generate Sparkle EdDSA keys and sync the public key into Info.plist.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLIC_KEY_FILE="$ROOT_DIR/config/sparkle-public-ed-key.txt"
INFO_PLIST="$ROOT_DIR/app/DiskWise/Info.plist"

bash "$ROOT_DIR/scripts/sparkle-tools.sh"

echo "==> Generating Sparkle signing keys (stored in your login keychain)"
OUTPUT="$("$ROOT_DIR/.sparkle-tools/bin/generate_keys")"
PUBLIC_KEY="$(echo "$OUTPUT" | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p' | head -1)"

if [[ -z "$PUBLIC_KEY" ]]; then
  echo "Could not parse public key from generate_keys output."
  echo "$OUTPUT"
  exit 1
fi

mkdir -p "$(dirname "$PUBLIC_KEY_FILE")"
printf '%s\n' "$PUBLIC_KEY" >"$PUBLIC_KEY_FILE"
echo "==> Saved public key → $PUBLIC_KEY_FILE"

if [[ -f "$INFO_PLIST" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" "$INFO_PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $PUBLIC_KEY" "$INFO_PLIST"
  echo "==> Updated SUPublicEDKey in Info.plist"
fi

echo ""
echo "For CI releases, export the private key:"
echo "  export SPARKLE_PRIVATE_KEY=\"\$(generate_exported_private_key)\""
echo ""
echo "Store SPARKLE_PRIVATE_KEY as a GitHub Actions secret for automated releases."
