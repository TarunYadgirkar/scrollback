#!/usr/bin/env bash
# Builds a Release copy of the Mac app into /Applications. Full Disk Access is
# tied to the app's path and signature, so grant it to this copy, not a debug build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build/mac-release"

cd "$ROOT"
xcodegen generate --quiet
xcodebuild -project Scrollback.xcodeproj -scheme ScrollbackMac -configuration Release \
  -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates -quiet build

pkill -x Scrollback 2>/dev/null || true
rm -rf /Applications/Scrollback.app
cp -R "$BUILD_DIR/Build/Products/Release/Scrollback.app" /Applications/
open /Applications/Scrollback.app
echo "Installed /Applications/Scrollback.app."
