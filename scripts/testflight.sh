#!/usr/bin/env bash
# Archives the iPhone app and uploads it to App Store Connect for TestFlight.
# Needs: an App Store Connect app record for your <prefix>.scrollback bundle ID, and Apple's
# approval of Family Controls for distribution on the app and both extensions.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/config.sh"
require_team
BUILD_DIR="$ROOT/.build/testflight"
ARCHIVE="$BUILD_DIR/Scrollback.xcarchive"
OPTIONS="$BUILD_DIR/ExportOptions.plist"

mkdir -p "$BUILD_DIR"
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

key=$("$ROOT/scripts/peer-key.sh")
cd "$ROOT"
xcodegen generate --quiet
SCROLLBACK_PEER_KEY="$key" xcodebuild -project Scrollback.xcodeproj -scheme ScrollbackiOS -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates -quiet \
  CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" "${CONFIG_OVERRIDES[@]}" archive
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" -allowProvisioningUpdates
echo "Uploaded. It appears in App Store Connect → TestFlight after Apple finishes processing (usually 5–30 minutes)."
