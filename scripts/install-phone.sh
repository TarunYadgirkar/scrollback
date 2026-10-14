#!/usr/bin/env bash
# Builds the iPhone app with this Mac's sync key baked in and installs it over USB.
# Development profiles on the paid team last a year. Run with --if-stale from launchd
# to reinstall only when the code changed since the last install (or the build nears expiry).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$HOME/Library/Application Support/Scrollback/phone-installed-at"
STALE_AFTER_SECONDS=$((300 * 24 * 3600))
BUILD_DIR="$ROOT/.build/ios"

commit=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)
if [[ "${1:-}" == "--if-stale" && -f "$STAMP" ]]; then
  read -r installed_at installed_commit < "$STAMP" || true
  age=$(( $(date +%s) - ${installed_at:-0} ))
  if (( age < STALE_AFTER_SECONDS )) && [[ "${installed_commit:-}" == "$commit" ]]; then
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
# A fresh build number each install makes iOS re-index the app's Shortcuts actions.
SCROLLBACK_PEER_KEY="$key" xcodebuild -project Scrollback.xcodeproj -scheme ScrollbackiOS -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates -quiet \
  CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" build

app="$BUILD_DIR/Build/Products/Release-iphoneos/Scrollback.app"
xcrun devicectl device install app --device "$device" "$app"
mkdir -p "$(dirname "$STAMP")"
echo "$(date +%s) $commit" > "$STAMP"
echo "Installed Scrollback on your iPhone."
