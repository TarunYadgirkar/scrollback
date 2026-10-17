#!/usr/bin/env bash
# Loads CloudKit/schema.ckdb into the iCloud container's Development environment.
# Production is what every build uses, so afterwards open CloudKit Console →
# iCloud.com.example.scrollback → Schema → "Deploy Schema Changes…".
# First run only: `xcrun cktool save-token --type management` (opens the browser for a token).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
xcrun cktool validate-schema --team-id YOURTEAMID --container-id iCloud.com.example.scrollback \
  --environment development --file "$ROOT/CloudKit/schema.ckdb"
xcrun cktool import-schema --team-id YOURTEAMID --container-id iCloud.com.example.scrollback \
  --environment development --file "$ROOT/CloudKit/schema.ckdb"
echo "Loaded into Development. Now deploy it to Production: https://icloud.developer.apple.com/dashboard/"
