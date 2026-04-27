#!/usr/bin/env bash
# Vaultwarden backup. Invoked by systemd hourly (see flake.nix).
#
# This script holds NO configuration. All paths/hosts/retention come from
# environment variables set by the systemd unit, which sources them from
# flake.nix. Single source of truth: flake.nix.
#
# To test manually: `sudo systemctl start vaultwarden-backup.service` (the
# unit's Environment= block sets everything up). Running the script directly
# without those env vars will fail loudly — by design.
#
#   1. `vaultwarden backup` → atomic SQLite snapshot (Online Backup API).
#   2. Bundle snapshot + rsa_key.* + config.json + attachments + sends
#      into a tar.zst, encrypt with age (private key in 1Password only).
#   3. rsync to local Synology (SMB mount) and off-site Synology #2 (SSH).
#   4. Local retention = $VW_RETENTION_DAYS. Long-tail retention is on the Synologys.
#   5. Write $VW_STATE_FILE so Gatus can monitor freshness.

set -Eeuo pipefail

: "${VW_DATA_DIR:?must be set by systemd unit (see flake.nix)}"
: "${VW_LOCAL_DIR:?must be set by systemd unit}"
: "${VW_STATE_FILE:?must be set by systemd unit}"
: "${VW_AGE_RECIPIENT:?must be set by systemd unit}"
: "${VW_SYNOLOGY1_DIR:?must be set by systemd unit}"
: "${VW_SYNOLOGY2_HOST:?must be set by systemd unit}"
: "${VW_SYNOLOGY2_PATH:?must be set by systemd unit}"
: "${VW_RETENTION_DAYS:?must be set by systemd unit}"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
ARCHIVE="vaultwarden-${TS}.tar.zst.age"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
S1=skipped; S2=skipped; LOCAL=pending; ERR=""

log()  { printf '[vw-backup %s] %s\n' "$(date -u +%H:%M:%SZ)" "$*"; }
fail() { ERR="$*"; log "ERROR: $*"; write_state; exit 1; }

write_state() {
    local size=0 sha=""
    [[ -f "$VW_LOCAL_DIR/$ARCHIVE" ]] && {
        size=$(stat -c %s "$VW_LOCAL_DIR/$ARCHIVE")
        sha=$(sha256sum "$VW_LOCAL_DIR/$ARCHIVE" | awk '{print $1}')
    }
    mkdir -p "$(dirname "$VW_STATE_FILE")"
    printf '{"timestamp":"%s","archive":"%s","size_bytes":%d,"sha256":"%s","local":"%s","synology1":"%s","synology2":"%s","error":"%s"}\n' \
        "$TS" "$ARCHIVE" "$size" "$sha" "$LOCAL" "$S1" "$S2" "${ERR//\"/\\\"}" >"$VW_STATE_FILE"
}

[[ -d "$VW_DATA_DIR" ]]      || fail "missing $VW_DATA_DIR"
[[ -f "$VW_AGE_RECIPIENT" ]] || fail "missing age recipient $VW_AGE_RECIPIENT (see README §age setup)"
docker ps --format '{{.Names}}' | grep -qx vaultwarden || fail "vaultwarden container not running"
mkdir -p "$VW_LOCAL_DIR"

log "snapshotting database via 'vaultwarden backup'"
docker exec vaultwarden /vaultwarden backup >/dev/null || fail "'vaultwarden backup' failed"
SNAPSHOT=$(ls -t "$VW_DATA_DIR"/db_*.sqlite3 2>/dev/null | head -1)
[[ -n "$SNAPSHOT" ]] || fail "no db_*.sqlite3 produced"

mkdir -p "$STAGE/payload"
mv "$SNAPSHOT" "$STAGE/payload/db.sqlite3"
for f in rsa_key.pem rsa_key.der rsa_key.pub.pem rsa_key.pub.der config.json; do
    [[ -f "$VW_DATA_DIR/$f" ]] && cp "$VW_DATA_DIR/$f" "$STAGE/payload/"
done
[[ -d "$VW_DATA_DIR/attachments" ]] && cp -a "$VW_DATA_DIR/attachments" "$STAGE/payload/" || true
[[ -d "$VW_DATA_DIR/sends" ]]       && cp -a "$VW_DATA_DIR/sends"       "$STAGE/payload/" || true

log "encrypting → $ARCHIVE"
tar -C "$STAGE" -cf - payload | zstd -19 -T0 --quiet | age -R "$VW_AGE_RECIPIENT" -o "$VW_LOCAL_DIR/$ARCHIVE"
SIZE=$(stat -c %s "$VW_LOCAL_DIR/$ARCHIVE")
(( SIZE > 1024 )) || fail "archive suspiciously small ($SIZE bytes)"
LOCAL=ok
log "local: $VW_LOCAL_DIR/$ARCHIVE ($SIZE bytes)"

find "$VW_LOCAL_DIR" -maxdepth 1 -name 'vaultwarden-*.tar.zst.age' -mtime "+$VW_RETENTION_DAYS" -delete

SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=30 -o ServerAliveInterval=15 -o StrictHostKeyChecking=accept-new"
RSYNC_ARGS=(-a --delete --include='vaultwarden-*.tar.zst.age' --exclude='*' "$VW_LOCAL_DIR/")

log "rsync → Synology #1 ($VW_SYNOLOGY1_DIR)"
if stat "$VW_SYNOLOGY1_DIR" >/dev/null 2>&1 || mkdir -p "$VW_SYNOLOGY1_DIR" 2>/dev/null; then
    rsync "${RSYNC_ARGS[@]}" "$VW_SYNOLOGY1_DIR/" && S1=ok || S1=rsync_failed
else
    S1=not_mounted
fi

log "rsync → Synology #2 ($VW_SYNOLOGY2_HOST:$VW_SYNOLOGY2_PATH)"
if ssh $SSH_OPTS "$VW_SYNOLOGY2_HOST" "mkdir -p '$VW_SYNOLOGY2_PATH'" 2>/dev/null; then
    rsync "${RSYNC_ARGS[@]}" --rsync-path=/usr/bin/rsync -e "ssh $SSH_OPTS" "$VW_SYNOLOGY2_HOST:$VW_SYNOLOGY2_PATH/" && S2=ok || S2=rsync_failed
else
    S2=ssh_failed
fi

write_state
log "done. local=$LOCAL synology1=$S1 synology2=$S2"

# Local-only success is not enough for a password vault.
[[ "$S1" == "ok" || "$S2" == "ok" ]] || { log "ERROR: both Synology targets failed"; exit 2; }
