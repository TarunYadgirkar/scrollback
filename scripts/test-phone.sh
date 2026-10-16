#!/usr/bin/env bash
# Runs the UI tests on the plugged-in iPhone and saves their screenshots to assets/generated/ui-test/.
# The phone must be unlocked. The tested build stays installed, sync key included.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESULT="$ROOT/.build/ui-test.xcresult"
SHOTS="$ROOT/assets/generated/ui-test"

device=$("$ROOT/scripts/phone-udid.sh")
if [[ -z "$device" ]]; then
  echo "No iPhone connected. Plug it in with a cable, unlock it, and trust this Mac." >&2
  exit 1
fi

key=$("$ROOT/scripts/peer-key.sh")
cd "$ROOT"
xcodegen generate --quiet
rm -rf "$RESULT" "$SHOTS"
status=0
SCROLLBACK_PEER_KEY="$key" xcodebuild -project Scrollback.xcodeproj -scheme ScrollbackiOS -configuration Release \
  -destination "id=$device" -derivedDataPath "$ROOT/.build/ios" -resultBundlePath "$RESULT" -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" test "$@" || status=$?

mkdir -p "$SHOTS"
xcrun xcresulttool export attachments --path "$RESULT" --output-path "$SHOTS" >/dev/null || true
echo "Screenshots: $SHOTS"
exit $status
