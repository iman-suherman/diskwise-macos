#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
CONFIGURATION="${1:-debug}"

echo "==> Building DiskWise packages"
cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required to generate the app project."
  echo "Install with: brew install xcodegen"
  exit 1
fi

echo "==> Generating app icon from app/DiskWise/Assets/AppIconSource.raw.png"
swift "$ROOT_DIR/scripts/generate-app-icon.swift" \
  "$APP_DIR/DiskWise/Assets.xcassets/AppIcon.appiconset"

echo "==> Generating dock scanning icon from app/DiskWise/Assets/DockScanning.raw.png"
swift "$ROOT_DIR/scripts/prepare-dock-scanning-icon.swift"

echo "==> Generating Xcode project"
cd "$APP_DIR"
xcodegen generate

XCODE_CONFIG="Debug"
case "$CONFIGURATION" in
  [Rr][Ee][Ll][Ee][Aa][Ss][Ee])
    XCODE_CONFIG="Release"
    ;;
esac

echo "==> Building DiskWise.app ($XCODE_CONFIG)"
if ! xcodebuild \
  -project DiskWise.xcodeproj \
  -scheme DiskWise \
  -configuration "$XCODE_CONFIG" \
  -derivedDataPath "$ROOT_DIR/.build/DerivedData" \
  build; then
  echo "xcodebuild failed. If this is a fresh Xcode install, run: npm run setup:xcode"
  exit 1
fi

APP_PATH="$ROOT_DIR/.build/DerivedData/Build/Products/$XCODE_CONFIG/DiskWise.app"
if [[ -d "$APP_PATH" ]]; then
  ICNS_SOURCE="$APP_DIR/DiskWise/Assets/AppIcon.icns"
  if [[ -f "$ICNS_SOURCE" ]]; then
    cp "$ICNS_SOURCE" "$APP_PATH/Contents/Resources/AppIcon.icns"
  fi
  touch "$APP_PATH"
  /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$APP_PATH"
  echo "Built: $APP_PATH"
else
  echo "Build finished. Locate DiskWise.app under .build/DerivedData/Build/Products/"
fi
