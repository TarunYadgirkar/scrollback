#!/usr/bin/env bash
# Prints the UDID of the plugged-in iPhone (not a simulator or a watch), or nothing.
set -euo pipefail

devices_json=$(mktemp)
trap 'rm -f "$devices_json"' EXIT
xcrun devicectl list devices --json-output "$devices_json" >/dev/null 2>&1 || true
python3 -I - "$devices_json" <<'PY'
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
