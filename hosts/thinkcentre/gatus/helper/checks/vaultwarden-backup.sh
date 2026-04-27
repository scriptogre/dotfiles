#!/bin/sh
# Reports the freshness and target-status of the most recent Vaultwarden
# backup, by reading the state file the backup script writes.

STATE_FILE="/hostfs/var/lib/vaultwarden/last-backup.json"
MAX_AGE_SECONDS=$((25 * 3600))   # 25h — backup runs hourly, allow one miss

if [ ! -f "$STATE_FILE" ]; then
    echo "Status: 503 Service Unavailable"
    echo "Content-Type: application/json"
    echo ""
    echo '{"status":"unhealthy","message":"no backup state file at '"$STATE_FILE"'"}'
    exit 0
fi

# State file is a single-line JSON object; parse the bits we need with sed.
ts=$(sed -n 's/.*"timestamp":"\([^"]*\)".*/\1/p' "$STATE_FILE")
local_status=$(sed -n 's/.*"local":"\([^"]*\)".*/\1/p' "$STATE_FILE")
syn1=$(sed -n 's/.*"synology1":"\([^"]*\)".*/\1/p' "$STATE_FILE")
syn2=$(sed -n 's/.*"synology2":"\([^"]*\)".*/\1/p' "$STATE_FILE")

# Convert the ISO-8601 UTC timestamp (YYYYMMDDTHHMMSSZ) to epoch.
ts_epoch=$(date -d "${ts:0:4}-${ts:4:2}-${ts:6:2}T${ts:9:2}:${ts:11:2}:${ts:13:2}Z" +%s 2>/dev/null || echo 0)
now=$(date +%s)
age=$((now - ts_epoch))

unhealthy_reasons=""
[ "$local_status" != "ok" ]            && unhealthy_reasons="${unhealthy_reasons}local=$local_status "
[ "$syn1" != "ok" ] && [ "$syn2" != "ok" ] && unhealthy_reasons="${unhealthy_reasons}both-synologys-failed "
[ "$age" -gt "$MAX_AGE_SECONDS" ]      && unhealthy_reasons="${unhealthy_reasons}stale(${age}s) "

if [ -n "$unhealthy_reasons" ]; then
    echo "Status: 503 Service Unavailable"
    echo "Content-Type: application/json"
    echo ""
    echo "{\"status\":\"unhealthy\",\"timestamp\":\"$ts\",\"age_seconds\":$age,\"local\":\"$local_status\",\"synology1\":\"$syn1\",\"synology2\":\"$syn2\",\"reasons\":\"$unhealthy_reasons\"}"
else
    echo "Content-Type: application/json"
    echo ""
    echo "{\"status\":\"healthy\",\"timestamp\":\"$ts\",\"age_seconds\":$age,\"local\":\"$local_status\",\"synology1\":\"$syn1\",\"synology2\":\"$syn2\"}"
fi
