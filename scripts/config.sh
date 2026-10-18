# Sourced by the other scripts. Reads your Team ID and bundle ID prefix from Config/Secrets.xcconfig
# (falling back to Config/Base.xcconfig), unless TEAM_ID or BUNDLE_ID_PREFIX is already set.
# Pass "${CONFIG_OVERRIDES[@]}" to xcodebuild so environment values win over the xcconfig too.

config_value() {
  local key=$1 file value
  for file in "$ROOT/Config/Secrets.xcconfig" "$ROOT/Config/Base.xcconfig"; do
    [[ -f "$file" ]] || continue
    value=$(sed -n "s|^[[:space:]]*$key[[:space:]]*=[[:space:]]*\([^/[:space:]]*\).*|\1|p" "$file" | tail -n 1)
    if [[ -n "$value" ]]; then
      echo "$value"
      return
    fi
  done
}

TEAM_ID="${TEAM_ID:-$(config_value DEVELOPMENT_TEAM)}"
BUNDLE_ID_PREFIX="${BUNDLE_ID_PREFIX:-$(config_value BUNDLE_ID_PREFIX)}"
BUNDLE_ID="$BUNDLE_ID_PREFIX.scrollback"
ICLOUD_CONTAINER="iCloud.$BUNDLE_ID"
CONFIG_OVERRIDES=(DEVELOPMENT_TEAM="$TEAM_ID" BUNDLE_ID_PREFIX="$BUNDLE_ID_PREFIX")

require_team() {
  if [[ -z "$TEAM_ID" ]]; then
    echo "No Apple Team ID set. Copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig and fill it in, or export TEAM_ID." >&2
    exit 1
  fi
}
