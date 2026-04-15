#!/bin/sh
API="http://192.168.0.12:8384/rest/db/status?folder=zd26e-jmupe"

response=$(curl -s -H "X-API-Key: ${SYNCTHING_API_KEY}" "$API" 2>/dev/null)

if [ -z "$response" ]; then
  echo "Status: 503 Service Unavailable"
  echo "Content-Type: application/json"
  echo ""
  echo "{\"status\":\"unhealthy\",\"message\":\"Cannot reach Syncthing API\"}"
  exit 0
fi

errors=$(echo "$response" | jq -r '.errors // 0')
state=$(echo "$response" | jq -r '.state // "unknown"')

if [ "$errors" != "0" ] && [ "$errors" != "null" ]; then
  echo "Status: 503 Service Unavailable"
  echo "Content-Type: application/json"
  echo ""
  echo "{\"status\":\"unhealthy\",\"message\":\"Syncthing folder errors: ${errors}\",\"state\":\"${state}\"}"
else
  echo "Content-Type: application/json"
  echo ""
  echo "{\"status\":\"healthy\",\"state\":\"${state}\"}"
fi
