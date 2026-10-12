#!/usr/bin/env bash
# Prints the Mac<->iPhone sync key, creating it on first run.
# Same file PeerKey.loadOrCreateOnMac() reads.
set -euo pipefail

key_file="$HOME/Library/Application Support/Scrollback/peer.key"

if [[ ! -s "$key_file" ]]; then
  mkdir -p "$(dirname "$key_file")"
  # noclobber makes the create atomic (O_EXCL), so a racing app launch can't end up with a different key.
  (umask 077 && set -o noclobber && openssl rand -base64 32 > "$key_file") 2>/dev/null || true
fi

tr -d '[:space:]' < "$key_file"
echo
