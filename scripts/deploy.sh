#!/bin/bash
# Build and deploy Hard Way Home to a connected iPhone.
# Usage: ./scripts/deploy.sh

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="HardWayHome"
DEVICE_ID="00008101-001344591151003A"

echo "==> Generating build info..."
./scripts/generate-build-info.sh

echo "==> Generating Xcode project..."
xcodegen generate

echo "==> Building for device..."
xcodebuild build \
  -project HardWayHome.xcodeproj \
  -scheme "$SCHEME" \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -allowProvisioningUpdates \
  -quiet

echo "==> Installing on device..."
# Find the .app in DerivedData
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/HardWayHome-*/Build/Products/Debug-iphoneos -name "HardWayHome.app" -maxdepth 1 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
  echo "ERROR: Could not find built .app — trying with explicit derivedDataPath..."
  xcodebuild build \
    -project HardWayHome.xcodeproj \
    -scheme "$SCHEME" \
    -destination "platform=iOS,id=$DEVICE_ID" \
    -allowProvisioningUpdates \
    -derivedDataPath build \
    -quiet
  APP_PATH="build/Build/Products/Debug-iphoneos/HardWayHome.app"
fi

echo "==> App at: $APP_PATH"

# ios-deploy if available, otherwise devicectl
if command -v ios-deploy &>/dev/null; then
  echo "==> Launching via ios-deploy..."
  ios-deploy --bundle "$APP_PATH" --id "$DEVICE_ID"
elif command -v xcrun &>/dev/null; then
  echo "==> Launching via devicectl..."
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
  xcrun devicectl device process launch --device "$DEVICE_ID" com.gwynmorfey.hardwayhome.native
else
  echo "==> Built successfully. Open Xcode and hit Cmd+R, or install ios-deploy:"
  echo "    brew install ios-deploy"
fi

echo "==> Done!"
