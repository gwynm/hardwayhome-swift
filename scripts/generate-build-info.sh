#!/bin/bash
# Generate BuildInfo.swift with git sha and build date.
# Called as an Xcode build phase or from deploy.sh.

set -euo pipefail

cd "$(dirname "$0")/.."

GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date -u +"%Y-%m-%d %H:%M UTC")

cat > HardWayHome/BuildInfo.swift << SWIFT
// Auto-generated — do not edit.
enum BuildInfo {
    static let gitSha = "$GIT_SHA"
    static let buildDate = "$BUILD_DATE"
}
SWIFT
