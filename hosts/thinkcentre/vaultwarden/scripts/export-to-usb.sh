#!/usr/bin/env bash
# Monthly offline export. Uses the official Bitwarden CLI to dump your vault
# as account-encrypted JSON (decrypt later with your master password — works
# even if Vaultwarden itself is dead).
#
# Run from your Mac (where bw and a USB drive are accessible):
#   ./export-to-usb.sh /Volumes/USB/vaultwarden-backups
#
# Pre-req: `bun add -g @bitwarden/cli` (or `brew install bitwarden-cli`).
# First time only: `bw config server https://vault.christiantanul.com`

set -Eeuo pipefail

DEST="${1:?destination directory required (e.g. /Volumes/USB/vaultwarden-backups)}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$DEST/vaultwarden-export-${TS}.encrypted.json"

[[ -d "$DEST" ]] || { echo "destination not mounted/writable: $DEST"; exit 1; }
command -v bw >/dev/null || { echo "bw CLI not found; install with: bun add -g @bitwarden/cli"; exit 1; }

# Make sure we're pointed at the self-hosted server, not bitwarden.com.
SERVER="$(bw config server | tr -d '"' || true)"
if [[ "$SERVER" != "https://vault.christiantanul.com" ]]; then
    echo "configuring bw server → https://vault.christiantanul.com"
    bw config server https://vault.christiantanul.com
fi

# Login if needed; unlock to get a session key.
if ! bw login --check >/dev/null 2>&1; then
    echo "logging in to Vaultwarden..."
    bw login
fi
SESSION="$(bw unlock --raw)"

echo "exporting → $OUT"
BW_SESSION="$SESSION" bw export --format encrypted_json --output "$OUT"
BW_SESSION="$SESSION" bw lock >/dev/null

echo "done. file: $OUT"
echo "decrypt later: bw import bitwardenjson '$OUT' (and supply master password when prompted)"
