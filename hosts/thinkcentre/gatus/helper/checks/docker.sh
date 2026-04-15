#!/bin/sh
containers=$(curl -s --unix-socket /var/run/docker.sock \
  "http://localhost/containers/json?all=true" 2>/dev/null)

if [ -z "$containers" ]; then
  echo "Status: 503 Service Unavailable"
  echo "Content-Type: application/json"
  echo ""
  echo "{\"status\":\"unhealthy\",\"message\":\"Cannot reach Docker API\"}"
  exit 0
fi

problem_list=$(echo "$containers" | jq -r '
  .[] |
  select(.Names[0] | test("gatus") | not) |
  select(
    (.State == "exited") or
    (.Status | test("unhealthy"))
  ) |
  "\(.Names[0] | ltrimstr("/")): \(.Status)"
' 2>/dev/null)

if [ -n "$problem_list" ]; then
  escaped=$(echo "$problem_list" | tr '\n' '; ' | sed 's/; $//')
  echo "Status: 503 Service Unavailable"
  echo "Content-Type: application/json"
  echo ""
  echo "{\"status\":\"unhealthy\",\"message\":\"Problem containers: ${escaped}\"}"
else
  echo "Content-Type: application/json"
  echo ""
  echo "{\"status\":\"healthy\",\"message\":\"All containers running\"}"
fi
