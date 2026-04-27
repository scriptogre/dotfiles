#!/usr/bin/env bash
# Daily 1Password export → encrypted → both Synologys.
# Invoked by launchd (see launchd.nix). Skips silently if 1Password.app
# is locked (next day's run picks up the slack).

set -Eeuo pipefail

LOCAL_DIR="$HOME/Library/Application Support/onepassword-export"
AGE_RECIPIENT="$HOME/Projects/dotfiles/hosts/thinkcentre/vaultwarden/backup.age.pub"
SYNOLOGY1_HOST="chris@192.168.0.14"
SYNOLOGY2_HOST="chris@100.114.162.56"
# Relative to chris's home dir on each Synology — works regardless of whether
# homes live on /volume1 or /volume2 (the two NASes differ).
DEST_PATH="backups/onepassword-export"
RETENTION_DAYS=30

TS="$(date -u +%Y%m%dT%H%M%SZ)"
ARCHIVE="onepassword-${TS}.tar.zst.age"
STAGE="$(mktemp -d -t op-export-XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

log() { printf '[op-export %s] %s\n' "$(date -u +%H:%M:%SZ)" "$*"; }

mkdir -p "$LOCAL_DIR"
mkdir -p "$STAGE/payload"

# Skip if 1Password isn't unlocked.
if ! op vault list --format=json >"$STAGE/payload/vaults.json" 2>/dev/null; then
    log "1Password not unlocked or signed in; skipping today's export"
    exit 0
fi

log "iterating vaults + items + documents"
while IFS= read -r vault_id; do
    vault_dir="$STAGE/payload/$vault_id"
    mkdir -p "$vault_dir/documents"
    op item list --vault="$vault_id" --format=json >"$vault_dir/items-list.json"
    while IFS= read -r item_id; do
        op item get "$item_id" --vault="$vault_id" --format=json >"$vault_dir/$item_id.json"
    done < <(jq -r '.[].id' "$vault_dir/items-list.json")

    # Documents (1P "Documents" category) — file content + metadata.
    op document list --vault="$vault_id" --format=json >"$vault_dir/documents-list.json" 2>/dev/null || echo "[]" >"$vault_dir/documents-list.json"
    while IFS= read -r doc_id; do
        [[ -z "$doc_id" ]] && continue
        op document get "$doc_id" --vault="$vault_id" --output "$vault_dir/documents/$doc_id" 2>/dev/null || true
    done < <(jq -r '.[].id // empty' "$vault_dir/documents-list.json")
done < <(jq -r '.[].id' "$STAGE/payload/vaults.json")

ITEM_COUNT=$(find "$STAGE/payload" -name '*.json' -not -name 'items-list.json' -not -name 'documents-list.json' -not -name 'vaults.json' | wc -l | tr -d ' ')
DOC_COUNT=$(find "$STAGE/payload" -path '*/documents/*' -type f | wc -l | tr -d ' ')
log "captured $ITEM_COUNT items + $DOC_COUNT documents"

log "encrypting → $ARCHIVE"
tar -C "$STAGE" -cf - payload | zstd -19 -T0 --quiet | age -R "$AGE_RECIPIENT" -o "$LOCAL_DIR/$ARCHIVE"
SIZE=$(stat -f %z "$LOCAL_DIR/$ARCHIVE")
log "local: $LOCAL_DIR/$ARCHIVE ($SIZE bytes)"

# Local retention
find "$LOCAL_DIR" -maxdepth 1 -name 'onepassword-*.tar.zst.age' -mtime "+$RETENTION_DAYS" -delete

SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=30 -o StrictHostKeyChecking=accept-new"
RSYNC_ARGS=(-a --delete --include='onepassword-*.tar.zst.age' --exclude='*' "$LOCAL_DIR/")

push() {
    local host="$1"
    log "rsync → $host:$DEST_PATH"
    if ssh $SSH_OPTS "$host" "mkdir -p '$DEST_PATH'" 2>/dev/null; then
        rsync "${RSYNC_ARGS[@]}" --rsync-path=/usr/bin/rsync -e "ssh $SSH_OPTS" "$host:$DEST_PATH/" \
            && log "  ok" || log "  FAILED"
    else
        log "  ssh failed"
    fi
}

push "$SYNOLOGY1_HOST"
push "$SYNOLOGY2_HOST"

log "done"
