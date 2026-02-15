#!/bin/bash
# Take README screenshots on the iOS Simulator.
# Requires: app built + installed on "iPhone 16 Pro" sim with seed data.
# Usage: ./scripts/screenshots.sh

set -euo pipefail

cd "$(dirname "$0")/.."

SIM="iPhone 16 Pro"
BUNDLE="com.gwynmorfey.hardwayhome.native"
OUT="assets/screenshots"

mkdir -p "$OUT"

echo "==> Terminating any running instance..."
xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true

echo "==> Launching app..."
xcrun simctl launch "$SIM" "$BUNDLE"
sleep 2

echo "==> Home screen..."
xcrun simctl io "$SIM" screenshot "$OUT/home.png"

echo "==> Tapping first workout row for detail..."
# Tap first workout row (approximate y for first row)
xcrun simctl io "$SIM" screenshot --type=png /dev/null 2>/dev/null  # warm up
# Use xcrun simctl to send a UI interaction isn't possible, so we use the
# Mobile MCP or manual interaction. For automated screenshots, build the app
# with seed data and use XCUITest instead.
echo ""
echo "NOTE: Automated navigation is not supported via simctl."
echo "Use Mobile MCP or take screenshots manually:"
echo "  1. Home screen  -> $OUT/home.png        (already captured)"
echo "  2. Tap a workout -> $OUT/workout-detail.png"
echo "  3. Back, tap Start, simulate GPS -> $OUT/workout.png"
echo "  4. Stop workout, tap Settings gear -> $OUT/settings.png"
echo ""
echo "Quick manual capture:"
echo "  xcrun simctl io '$SIM' screenshot $OUT/<name>.png"
echo ""
echo "==> Done (home screenshot saved, others need manual navigation)."
