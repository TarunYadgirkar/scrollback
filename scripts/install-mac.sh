#!/usr/bin/env bash
# Archives the Mac app, signs it with the team's Developer ID, has Apple notarize it, and installs
# the stapled copy into /Applications. Notarization uses the Apple ID Xcode is signed in to, the same
# one scripts/testflight.sh uploads with. Pass --skip-notarize for a quick Developer ID build that
# skips Apple's check (it still runs locally, just without the notarization ticket).
#
# Full Disk Access is tied to the app's path and signature, so grant it to this copy, not a debug
# build. The first install after switching signatures needs it granted once more.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build/mac-release"
ARCHIVE="$BUILD_DIR/Scrollback.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
OPTIONS="$BUILD_DIR/ExportOptions.plist"
NOTARIZE=true
[[ "${1:-}" == "--skip-notarize" ]] && NOTARIZE=false

destination=export
$NOTARIZE && destination=upload

rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR"
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>destination</key><string>$destination</string>
  <key>teamID</key><string>YOURTEAMID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

cd "$ROOT"
xcodegen generate --quiet
xcodebuild -project Scrollback.xcodeproj -scheme ScrollbackMac -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates -quiet archive
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" \
  -exportPath "$EXPORT_DIR" -allowProvisioningUpdates

if $NOTARIZE; then
  # The upload above submits to Apple's notary service; this fetches the stapled app once it's accepted.
  echo "Waiting for Apple to notarize Scrollback (usually a few minutes)…"
  for _ in $(seq 1 60); do
    if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" >/dev/null 2>&1; then
      break
    fi
    sleep 30
  done
  xcrun stapler validate "$EXPORT_DIR/Scrollback.app"
fi

codesign --verify --deep --strict "$EXPORT_DIR/Scrollback.app"
# Gatekeeper only accepts the notarized copy, so only check that one.
$NOTARIZE && spctl --assess --type execute --verbose "$EXPORT_DIR/Scrollback.app"

pkill -x Scrollback 2>/dev/null || true
rm -rf /Applications/Scrollback.app
cp -R "$EXPORT_DIR/Scrollback.app" /Applications/
open /Applications/Scrollback.app
echo "Installed /Applications/Scrollback.app ($($NOTARIZE && echo "signed and notarized" || echo "signed, not notarized"))."
