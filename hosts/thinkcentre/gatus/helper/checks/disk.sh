#!/bin/sh
THRESHOLD=85
unhealthy=""
results="["
first=true

for mount in / /home /mnt/nas/media /mnt/nas/media_server /mnt/nas/homes; do
  hostfs_path="/hostfs${mount}"
  if [ ! -d "$hostfs_path" ]; then
    continue
  fi
  pct=$(df "$hostfs_path" 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
  if [ -z "$pct" ]; then
    continue
  fi
  $first || results="${results},"
  first=false
  results="${results}{\"mount\":\"${mount}\",\"usage_pct\":${pct}}"
  if [ "$pct" -ge "$THRESHOLD" ]; then
    unhealthy="${unhealthy} ${mount}(${pct}%)"
  fi
done

results="${results}]"

if [ -n "$unhealthy" ]; then
  echo "Status: 503 Service Unavailable"
  echo "Content-Type: application/json"
  echo ""
  echo "{\"status\":\"unhealthy\",\"message\":\"High disk usage:${unhealthy}\",\"mounts\":${results}}"
else
  echo "Content-Type: application/json"
  echo ""
  echo "{\"status\":\"healthy\",\"mounts\":${results}}"
fi
