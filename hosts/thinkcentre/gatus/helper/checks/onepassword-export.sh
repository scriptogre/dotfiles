#!/bin/sh
# Reports the freshness of the most recent 1Password export archive on the
# local Synology mount. Mac pushes daily; allow up to 36h to tolerate one
# missed run (laptop closed, 1P locked at 13:00, etc.).

DIR="/hostfs/mnt/nas/homes/chris/backups/onepassword-export"
MAX_AGE_SECONDS=$((36 * 3600))

if [ ! -d "$DIR" ]; then
    echo "Status: 503 Service Unavailable"
    echo "Content-Type: application/json"
    echo ""
    echo '{"status":"unhealthy","message":"export directory missing on Synology #1"}'
    exit 0
fi

NEWEST=$(ls -t "$DIR"/onepassword-*.tar.zst.age 2>/dev/null | head -1)
if [ -z "$NEWEST" ]; then
    echo "Status: 503 Service Unavailable"
    echo "Content-Type: application/json"
    echo ""
    echo '{"status":"unhealthy","message":"no 1P export archives present"}'
    exit 0
fi

mtime=$(stat -c %Y "$NEWEST" 2>/dev/null || echo 0)
now=$(date +%s)
age=$((now - mtime))
size=$(stat -c %s "$NEWEST" 2>/dev/null || echo 0)
filename=$(basename "$NEWEST")

if [ "$age" -gt "$MAX_AGE_SECONDS" ]; then
    echo "Status: 503 Service Unavailable"
    echo "Content-Type: application/json"
    echo ""
    echo "{\"status\":\"unhealthy\",\"newest\":\"$filename\",\"age_seconds\":$age,\"size_bytes\":$size,\"reason\":\"stale (>36h)\"}"
else
    echo "Content-Type: application/json"
    echo ""
    echo "{\"status\":\"healthy\",\"newest\":\"$filename\",\"age_seconds\":$age,\"size_bytes\":$size}"
fi
