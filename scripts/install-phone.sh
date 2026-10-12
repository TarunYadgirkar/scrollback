#!/usr/bin/env bash
# Builds the iPhone app with this Mac's sync key baked in and installs it over USB.
# Free Apple developer accounts sign builds for 7 days; run with --if-stale from
# launchd to reinstall only when the installed build is older than 5 days.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$HOME/Library/Application Support/Scrollback/phone-installed-at"
STALE_AFTER_SECONDS=$((5 * 24 * 3600))
BUILD_DIR="$ROOT/.build/ios"

if [[ "${1:-}" == "--if-stale" && -f "$STAMP" ]]; then
  age=$(( $(date +%s) - $(cat "$STAMP") ))
  if (( age < STALE_AFTER_SECONDS )); then
    exit 0
  fi
fi

devices_json=$(mktemp)
trap 'rm -f "$devices_json"' EXIT
xcrun devicectl list devices --json-output "$devices_json" >/dev/null 2>&1 || true
device=$(python3 -I - "$devices_json" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for d in devices:
    hw = d.get("hardwareProperties", {})
    if hw.get("reality") == "physical" and hw.get("deviceType") == "iPhone" \
            and d.get("connectionProperties", {}).get("tunnelState") != "unavailable":
        print(hw.get("udid") or d["identifier"])
        break
PY
)
if [[ -z "$device" ]]; then
  [[ "${1:-}" == "--if-stale" ]] && exit 0
  echo "No iPhone connected. Plug it in with a cable, unlock it, and trust this Mac." >&2
  exit 1
fi

key=$("$ROOT/scripts/peer-key.sh")

cd "$ROOT"
xcodegen generate --quiet
# Passed through the environment rather than argv so the key doesn't show up in `ps`.
SCROLLBACK_PEER_KEY="$key" xcodebuild -project Scrollback.xcodeproj -scheme ScrollbackiOS -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates -quiet build

app="$BUILD_DIR/Build/Products/Release-iphoneos/Scrollback.app"
xcrun devicectl device install app --device "$device" "$app"
mkdir -p "$(dirname "$STAMP")"
date +%s > "$STAMP"
echo "Installed Scrollback on your iPhone. It stays valid for 7 days; plug in again before then or let the launch agent handle it."
