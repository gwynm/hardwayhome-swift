#!/bin/bash
# Build and deploy Hard Way Home to a connected iPhone.
# Uses Release config to avoid iCloud/entitlement environment issues.
# Usage: ./scripts/deploy.sh

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="HardWayHome"
DEVICE_ID="00008101-001344591151003A"
ARCHIVE_PATH="build/HardWayHome.xcarchive"
EXPORT_PATH="build/export"
EXPORT_PLIST="build/ExportOptions.plist"

echo "==> Generating build info..."
./scripts/generate-build-info.sh

echo "==> Generating Xcode project..."
xcodegen generate

mkdir -p build
cat > "$EXPORT_PLIST" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>debugging</string>
    <key>teamID</key>
    <string>ZBH4BELMH2</string>
</dict>
</plist>
EOF

echo "==> Archiving (Release)..."
xcodebuild archive \
  -project HardWayHome.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -quiet

echo "==> Exporting IPA..."
rm -rf "$EXPORT_PATH"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST"

IPA_PATH="$EXPORT_PATH/HardWayHome.ipa"
if [ ! -f "$IPA_PATH" ]; then
  echo "ERROR: IPA not found at $IPA_PATH"
  exit 1
fi

echo "==> Installing on device..."
xcrun devicectl device install app --device "$DEVICE_ID" "$IPA_PATH"

echo "==> Launching..."
xcrun devicectl device process launch --device "$DEVICE_ID" com.gwynmorfey.hardwayhome.native

echo "==> Done!"
