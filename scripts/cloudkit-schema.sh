#!/usr/bin/env bash
# Loads CloudKit/schema.ckdb into the iCloud container's Development environment.
# Production is what every build uses, so afterwards open CloudKit Console →
# your iCloud.<prefix>.scrollback container → Schema → "Deploy Schema Changes…".
# First run only: `xcrun cktool save-token --type management` (opens the browser for a token).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/config.sh"
require_team
xcrun cktool validate-schema --team-id "$TEAM_ID" --container-id "$ICLOUD_CONTAINER" \
  --environment development --file "$ROOT/CloudKit/schema.ckdb"
xcrun cktool import-schema --team-id "$TEAM_ID" --container-id "$ICLOUD_CONTAINER" \
  --environment development --file "$ROOT/CloudKit/schema.ckdb"
echo "Loaded into $ICLOUD_CONTAINER (Development). Now deploy it to Production: https://icloud.developer.apple.com/dashboard/"
