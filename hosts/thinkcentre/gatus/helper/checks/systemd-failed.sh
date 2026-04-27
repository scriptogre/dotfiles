#!/bin/sh
# Reports any systemd units in `failed` state on the host. The host writes
# /run/systemd-failed.txt every minute (see gatus/systemd-failed-snapshot.nix).
# This check reads that file and flags both stale snapshots and any failures.

FILE="/hostfs/run/systemd-failed.txt"
MAX_STALE_SECONDS=$((5 * 60))   # snapshot timer fires every 60s; allow 5min slack

if [ ! -f "$FILE" ]; then
    echo "Status: 503 Service Unavailable"
    echo "Content-Type: application/json"
    echo ""
    echo '{"status":"unhealthy","message":"snapshot file missing — is systemd-failed-snapshot.timer running?"}'
    exit 0
fi

# Snapshot freshness — if the timer stopped, we want to know.
mtime=$(stat -c %Y "$FILE" 2>/dev/null || echo 0)
now=$(date +%s)
age=$((now - mtime))
if [ "$age" -gt "$MAX_STALE_SECONDS" ]; then
    echo "Status: 503 Service Unavailable"
    echo "Content-Type: application/json"
    echo ""
    echo "{\"status\":\"unhealthy\",\"reason\":\"snapshot stale (${age}s)\"}"
    exit 0
fi

# Empty file = no failures.
if [ ! -s "$FILE" ]; then
    echo "Content-Type: application/json"
    echo ""
    echo '{"status":"healthy","failed_units":[]}'
    exit 0
fi

# Non-empty — at least one failed unit.
units=$(tr '\n' ' ' < "$FILE" | sed 's/ *$//' | sed 's/"/\\"/g')
echo "Status: 503 Service Unavailable"
echo "Content-Type: application/json"
echo ""
echo "{\"status\":\"unhealthy\",\"failed_units\":\"$units\"}"
