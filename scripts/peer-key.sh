#!/usr/bin/env bash
# Prints the Mac<->iPhone sync key, creating it on first run.
# Same file PeerKey.loadOrCreateOnMac() reads.
set -euo pipefail

key_file="$HOME/Library/Application Support/Scrollback/peer.key"

if [[ ! -s "$key_file" ]]; then
  mkdir -p "$(dirname "$key_file")"
  (umask 077 && openssl rand -base64 32 > "$key_file")
  chmod 600 "$key_file"
fi

tr -d '[:space:]' < "$key_file"
echo
