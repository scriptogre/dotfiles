#!/usr/bin/env bash
# Restore a Vaultwarden backup archive.
#
# Default mode: verification — extracts the archive to a temp directory and
# lists its contents. Safe; touches nothing live.
#
# Apply mode (--apply): destructive. Stops the container, replaces the live
# data directory with the archive contents, restarts. Use only when you
# actually need to recover.
#
# Usage:
#   restore.sh <archive.tar.zst.age> <age-identity-file>            # verify
#   restore.sh <archive.tar.zst.age> <age-identity-file> --apply    # restore

set -Eeuo pipefail

ARCHIVE="${1:?archive path required}"
IDENTITY="${2:?age identity (private key) file required}"
MODE="${3:-verify}"

DATA_DIR="/var/lib/vaultwarden/data"
EXTRACT_DIR="$(mktemp -d -t vw-restore-XXXXXX)"
trap 'rm -rf "$EXTRACT_DIR"' EXIT

[[ -f "$ARCHIVE" ]]   || { echo "archive not found: $ARCHIVE"; exit 1; }
[[ -f "$IDENTITY" ]]  || { echo "age identity not found: $IDENTITY"; exit 1; }

echo "decrypting + extracting → $EXTRACT_DIR"
age -d -i "$IDENTITY" "$ARCHIVE" | zstd -d --quiet | tar -C "$EXTRACT_DIR" -xf -

echo "archive contents:"
find "$EXTRACT_DIR/payload" -maxdepth 2 -printf '  %p (%s bytes)\n' | sort

if [[ ! -f "$EXTRACT_DIR/payload/db.sqlite3" ]]; then
    echo "ERROR: payload/db.sqlite3 missing — archive may be corrupt"
    exit 2
fi

if [[ "$MODE" != "--apply" ]]; then
    echo
    echo "Verification only. Re-run with --apply to actually restore into $DATA_DIR."
    exit 0
fi

# ─── Apply mode (destructive) ────────────────────────────────────────────────
echo
read -rp "About to overwrite $DATA_DIR. Type RESTORE to proceed: " confirm
[[ "$confirm" == "RESTORE" ]] || { echo "aborted"; exit 0; }

BACKUP_OF_LIVE="${DATA_DIR}.pre-restore-$(date -u +%Y%m%dT%H%M%SZ)"
echo "stopping vaultwarden..."
docker stop vaultwarden >/dev/null

echo "moving current $DATA_DIR → $BACKUP_OF_LIVE (rollback safety net)"
mv "$DATA_DIR" "$BACKUP_OF_LIVE"
mkdir -p "$DATA_DIR"

echo "restoring archive payload → $DATA_DIR"
cp -a "$EXTRACT_DIR/payload/." "$DATA_DIR/"

# Critical (per Vaultwarden wiki): a stale db.sqlite3-wal file can corrupt
# the restored database when SQLite tries to "recover" the new db using the
# old WAL. The .backup snapshot doesn't include a WAL and doesn't need one.
rm -f "$DATA_DIR/db.sqlite3-wal" "$DATA_DIR/db.sqlite3-shm"

echo "starting vaultwarden..."
docker start vaultwarden >/dev/null

echo "done. live data restored. previous data preserved at: $BACKUP_OF_LIVE"
echo "verify the restore worked, then remove the safety backup with:"
echo "  sudo rm -rf '$BACKUP_OF_LIVE'"
