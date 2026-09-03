#!/usr/bin/env bash
# Capture DiskWiseiOS screens for App Store Connect (6.9" iPhone + 12.9" iPad).
# Uses DISKWISE_DEMO + DISKWISE_DEMO_ROUTE so each shot is a distinct clean screen.
# Erases the target App Store simulators first so leftover permission sheets
# (e.g. ArahBaik location) cannot appear in DiskWise metadata.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
OUT_IPHONE="$ROOT/app-store-connect/asc/iphone-69"
OUT_IPAD="$ROOT/app-store-connect/asc/ipad-13"
SCHEME=DiskWiseiOS
BUNDLE_ID=net.suherman.diskwise.ios
DERIVED="$ROOT/build/DerivedData-screenshots"
RAW_DIR="$ROOT/build/ios/screenshot-raw"

# Prefer dedicated App Store sims (shared HaloRT names are fine after erase).
IPHONE_NAME="${IPHONE_SIMULATOR:-HaloRT App Store iPhone 17 Pro Max}"
IPAD_NAME="${IPAD_SIMULATOR:-HaloRT App Store iPad Pro 13}"

SHOTS=(dashboard recommendations bucket confirm)

mkdir -p "$OUT_IPHONE" "$OUT_IPAD" "$RAW_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen required" >&2
  exit 1
fi
(cd "$APP_DIR" && xcodegen generate)

resolve_udid() {
  local name="$1"
  xcrun simctl list devices available | awk -F '[()]' -v n="$name" '
    index($0, n " (") && $0 !~ /unavailable/ { print $2; exit }
  '
}

prepare_simulator() {
  local name="$1"
  local udid
  udid="$(resolve_udid "$name")"
  if [[ -z "$udid" ]]; then
    echo "error: simulator not found: $name" >&2
    exit 1
  fi
  echo "Preparing clean simulator \"$name\" ($udid)…" >&2
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl erase "$udid"
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override \
    --time "9:41" \
    --dataNetwork wifi \
    --wifiBars 3 \
    --cellularMode active \
    --cellularBars 4 \
    --batteryState charged \
    --batteryLevel 100 \
    --operatorName "" >/dev/null 2>&1 || true
  printf '%s\n' "$udid"
}

echo "Building DiskWiseiOS Debug for simulator…"
IPHONE_UDID="$(prepare_simulator "$IPHONE_NAME")"
xcodebuild \
  -project "$APP_DIR/DiskWise.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$IPHONE_UDID" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -name 'DiskWiseiOS.app' -maxdepth 1 -print -quit)"
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "error: DiskWiseiOS.app not found after build" >&2
  exit 1
fi

capture_device() {
  local udid="$1"
  local out_dir="$2"
  local width="$3"
  local height="$4"
  local label="$5"

  mkdir -p "$out_dir"
  xcrun simctl install "$udid" "$APP"

  # Warm-up: first launch after erase often shows SpringBoard banners
  # (e.g. Apple Intelligence). Dismiss by home + settle before real shots.
  echo "  [$label] warm-up launch (discard)"
  SIMCTL_CHILD_DISKWISE_DEMO=1 \
    SIMCTL_CHILD_DISKWISE_DEMO_ROUTE=dashboard \
    xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" >/dev/null
  sleep 5
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  # Return to SpringBoard so any residual banner animates away.
  xcrun simctl launch "$udid" com.apple.springboard >/dev/null 2>&1 || true
  sleep 2

  local first=1
  for route in "${SHOTS[@]}"; do
    echo "  [$label] capture $route"
    xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
    SIMCTL_CHILD_DISKWISE_DEMO=1 \
      SIMCTL_CHILD_DISKWISE_DEMO_ROUTE="$route" \
      xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" >/dev/null
    if [[ "$first" -eq 1 ]]; then
      sleep 3.5
      first=0
    else
      sleep 2.5
    fi
    local raw="$RAW_DIR/${label}-${route}.png"
    xcrun simctl io "$udid" screenshot "$raw"
    sips -z "$height" "$width" "$raw" --out "$out_dir/${route}.png" >/dev/null
  done
}

# App Store 6.9" iPhone: 1320×2868; 12.9" iPad: 2048×2732
capture_device "$IPHONE_UDID" "$OUT_IPHONE" 1320 2868 "iphone"

IPAD_UDID="$(prepare_simulator "$IPAD_NAME")"
capture_device "$IPAD_UDID" "$OUT_IPAD" 2048 2732 "ipad"
# iPad listing uses dashboard / recommendations / bucket only
rm -f "$OUT_IPAD/confirm.png"

echo "Screenshots → $OUT_IPHONE and $OUT_IPAD"
