#!/usr/bin/env bash
# Regenerates the README screenshots in assets/generated/ from made-up demo data (DemoData.swift),
# never from your own history. Builds unsigned with the placeholder com.example prefix, so it needs
# no Apple account and doesn't touch your installed app's settings.
#   Mac window: drawn offscreen by the app itself (-demo YES -renderScreenshots).
#   iPhone: an iPhone simulator, booted for the shot and shut down after. Skip with --mac-only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/assets/generated"
BUILD_DIR="$ROOT/.build/screenshots"
UNSIGNED=(CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= BUNDLE_ID_PREFIX=com.example)
LOAD_SECONDS=6

cd "$ROOT"
xcodegen generate --quiet
mkdir -p "$OUT"

xcodebuild -project Scrollback.xcodeproj -scheme ScrollbackMac -configuration Debug -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$BUILD_DIR" -quiet "${UNSIGNED[@]}" build
"$BUILD_DIR/Build/Products/Debug/Scrollback.app/Contents/MacOS/Scrollback" -demo YES -renderScreenshots "$OUT"

[[ "${1:-}" == "--mac-only" ]] && exit 0

sim=$(xcrun simctl list devices available | sed -n 's/^ *iPhone [^(]*(\([0-9A-F-]\{36\}\)) (Shutdown).*/\1/p' | head -n 1)
if [[ -z "$sim" ]]; then
  echo "No shut-down iPhone simulator to use. Add one in Xcode → Window → Devices and Simulators." >&2
  exit 1
fi
trap 'xcrun simctl shutdown "$sim" 2>/dev/null || true' EXIT

xcodebuild -project Scrollback.xcodeproj -scheme ScrollbackiOS -configuration Debug -destination "platform=iOS Simulator,id=$sim" \
  -derivedDataPath "$BUILD_DIR" -quiet "${UNSIGNED[@]}" build
xcrun simctl boot "$sim"
xcrun simctl bootstatus "$sim" -b >/dev/null
xcrun simctl status_bar "$sim" override --dataNetwork wifi --wifiBars 3 --cellularBars 4 --batteryState charged --batteryLevel 100
xcrun simctl install "$sim" "$BUILD_DIR/Build/Products/Debug-iphonesimulator/Scrollback.app"
xcrun simctl launch "$sim" com.example.scrollback -demo YES >/dev/null
sleep "$LOAD_SECONDS"
xcrun simctl io "$sim" screenshot "$OUT/demo-iphone-app.png" >/dev/null
xcrun simctl uninstall "$sim" com.example.scrollback
echo "Wrote $OUT/demo-iphone-app.png"
