#!/usr/bin/env bash
# Archive DiskWiseiOS and upload to App Store Connect (TestFlight).
# Same mechanism as ArahBaik/HaloRT: xcodebuild archive + exportArchive (automatic signing),
# authenticated with ASC API key from halort-infra/.credentials/asc.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
ARCHIVE_PATH="${IOS_ARCHIVE_PATH:-$ROOT/build/ios/DiskWiseiOS.xcarchive}"
EXPORT_PATH="${IOS_EXPORT_PATH:-$ROOT/build/ios/export}"
EXPORT_OPTIONS="$ROOT/build/ios/ExportOptions.plist"
TEAM_ID="${DEVELOPMENT_TEAM:-Q3TXW887NM}"
BUNDLE_ID="net.suherman.diskwise.ios"
HALORT_INFRA="${HALORT_INFRA_ROOT:-$ROOT/../../halort/halort-infra}"
ASC_DIR="${ASC_CREDENTIALS_DIR:-$HALORT_INFRA/.credentials/asc}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required (brew install xcodegen)"
  exit 1
fi

ICON_SRC="$ROOT/website/public/app-icon.png"
ICON_DST="$APP_DIR/DiskWiseiOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
if [[ -f "$ICON_SRC" ]]; then
  sips -z 1024 1024 "$ICON_SRC" --out "$ICON_DST" >/dev/null
fi

echo "==> Generating Xcode project"
(cd "$APP_DIR" && xcodegen generate)

if ! grep -q "PRODUCT_BUNDLE_IDENTIFIER: ${BUNDLE_ID}" "$APP_DIR/project.yml"; then
  echo "error: iOS app must use PRODUCT_BUNDLE_IDENTIFIER ${BUNDLE_ID}"
  exit 1
fi

KEY_PATH="$(ls "$ASC_DIR"/AuthKey_*.p8 2>/dev/null | head -1 || true)"
ISSUER_FILE="$ASC_DIR/issuer-id.txt"
if [[ -z "$KEY_PATH" || ! -f "$ISSUER_FILE" ]]; then
  echo "error: ASC API key not found in ${ASC_DIR}"
  exit 1
fi
KEY_ID="$(basename "$KEY_PATH" .p8 | sed 's/^AuthKey_//')"
ISSUER_ID="$(tr -d '[:space:]' < "$ISSUER_FILE")"
mkdir -p "${HOME}/.appstoreconnect/private_keys"
cp -f "$KEY_PATH" "${HOME}/.appstoreconnect/private_keys/"

AUTH_ARGS=(
  -authenticationKeyPath "$KEY_PATH"
  -authenticationKeyID "$KEY_ID"
  -authenticationKeyIssuerID "$ISSUER_ID"
)
echo "Using ASC API key ${KEY_ID}"

mkdir -p "$(dirname "$ARCHIVE_PATH")" "$EXPORT_PATH"

MARKETING_VERSION="$(
  awk '/DiskWiseiOS:/,0' "$APP_DIR/project.yml" | awk '/MARKETING_VERSION:/ { gsub(/"/, "", $2); print $2; exit }'
)"
BUILD_NUMBER="$(
  awk '/DiskWiseiOS:/,0' "$APP_DIR/project.yml" | awk '/CURRENT_PROJECT_VERSION:/ { print $2; exit }'
)"
GIT_COMMIT="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
UPLOADED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
STATUS_FILE="$ROOT/app-store-connect/testflight-status.json"
mkdir -p "$(dirname "$STATUS_FILE")"

echo "Archiving DiskWiseiOS ${MARKETING_VERSION} (${BUILD_NUMBER}) — Release, generic iOS device…"
xcodebuild \
  -project "$APP_DIR/DiskWise.xcodeproj" \
  -scheme DiskWiseiOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  "${AUTH_ARGS[@]}" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  archive

cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>export</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
EOF

echo ""
echo "Exporting IPA…"
rm -rf "$EXPORT_PATH"
mkdir -p "$EXPORT_PATH"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates \
  "${AUTH_ARGS[@]}"

IPA="$(ls "$EXPORT_PATH"/*.ipa | head -1)"
echo "Uploading ${IPA} to App Store Connect (TestFlight)…"
xcrun altool --upload-app -f "$IPA" -t ios --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"

cat > "$STATUS_FILE" <<EOF
{
  "bundleId": "${BUNDLE_ID}",
  "marketingVersion": "${MARKETING_VERSION}",
  "buildNumber": "${BUILD_NUMBER}",
  "gitCommit": "${GIT_COMMIT}",
  "uploadedAt": "${UPLOADED_AT}",
  "note": "Written by scripts/publish-testflight.sh after a successful upload."
}
EOF

echo ""
echo "Uploaded DiskWiseiOS ${MARKETING_VERSION} (${BUILD_NUMBER}) to App Store Connect."
echo "Recorded TestFlight status in ${STATUS_FILE}"
echo "TestFlight processing usually takes a few minutes — check App Store Connect."
