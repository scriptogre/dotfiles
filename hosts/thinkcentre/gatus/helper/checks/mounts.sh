#!/bin/sh
failed=""
results="["
first=true

for mount in /mnt/nas/media /mnt/nas/media_server /mnt/nas/homes; do
  hostfs_path="/hostfs${mount}"
  $first || results="${results},"
  first=false
  if timeout 5 stat "$hostfs_path" >/dev/null 2>&1; then
    results="${results}{\"mount\":\"${mount}\",\"accessible\":true}"
  else
    results="${results}{\"mount\":\"${mount}\",\"accessible\":false}"
    failed="${failed} ${mount}"
  fi
done

results="${results}]"

if [ -n "$failed" ]; then
  echo "Status: 503 Service Unavailable"
  echo "Content-Type: application/json"
  echo ""
  echo "{\"status\":\"unhealthy\",\"message\":\"Inaccessible mounts:${failed}\",\"mounts\":${results}}"
else
  echo "Content-Type: application/json"
  echo ""
  echo "{\"status\":\"healthy\",\"mounts\":${results}}"
fi
