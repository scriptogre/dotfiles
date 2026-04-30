# Gatus Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Gatus monitoring on the ThinkCentre to monitor all homelab services, infrastructure, and system health, with email alerts via Resend.

**Architecture:** Two Docker containers — `gatus` (monitoring engine + dashboard) and `gatus-helper` (lightweight Alpine CGI server exposing system health checks). Both on the `proxy` network. Dashboard at `status.christiantanul.com` behind Caddy.

**Tech Stack:** Gatus (Go monitoring), busybox httpd (CGI server), shell scripts, Docker Compose, Caddy reverse proxy, Resend SMTP.

**Spec:** `docs/superpowers/specs/2026-04-15-gatus-monitoring-design.md`

---

### Task 1: Create helper check scripts

**Files:**
- Create: `hosts/thinkcentre/gatus/helper/checks/disk.sh`
- Create: `hosts/thinkcentre/gatus/helper/checks/docker.sh`
- Create: `hosts/thinkcentre/gatus/helper/checks/mounts.sh`
- Create: `hosts/thinkcentre/gatus/helper/checks/syncthing.sh`

These are CGI scripts for busybox httpd. Each outputs HTTP headers then JSON. Return 200 when healthy, 503 when not.

- [ ] **Step 1: Create disk.sh**

Create `hosts/thinkcentre/gatus/helper/checks/disk.sh`:

```sh
#!/bin/sh
# Checks disk usage on key mount points via /hostfs bind-mount.
# Returns 503 if any mount exceeds 85%.

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
```

- [ ] **Step 2: Create docker.sh**

Create `hosts/thinkcentre/gatus/helper/checks/docker.sh`:

```sh
#!/bin/sh
# Checks for unhealthy or exited containers via Docker socket.
# Returns 503 if any container is unhealthy or unexpectedly stopped.
# Ignores gatus and gatus-helper (ourselves).

containers=$(curl -s --unix-socket /var/run/docker.sock \
  "http://localhost/containers/json?all=true" 2>/dev/null)

if [ -z "$containers" ]; then
  echo "Status: 503 Service Unavailable"
  echo "Content-Type: application/json"
  echo ""
  echo "{\"status\":\"unhealthy\",\"message\":\"Cannot reach Docker API\"}"
  exit 0
fi

# Find containers that are exited or have unhealthy health status.
# Exclude gatus and gatus-helper from checks.
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
```

- [ ] **Step 3: Create mounts.sh**

Create `hosts/thinkcentre/gatus/helper/checks/mounts.sh`:

```sh
#!/bin/sh
# Checks if SMB mounts are accessible by stat-ing them via /hostfs.
# Returns 503 if any mount is inaccessible.

failed=""
results="["
first=true

for mount in /mnt/nas/media /mnt/nas/media_server /mnt/nas/homes; do
  hostfs_path="/hostfs${mount}"
  $first || results="${results},"
  first=false
  # Use timeout to avoid hanging on stale NFS/SMB mounts
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
```

- [ ] **Step 4: Create syncthing.sh**

Create `hosts/thinkcentre/gatus/helper/checks/syncthing.sh`:

```sh
#!/bin/sh
# Queries Syncthing REST API for folder sync status.
# Returns 503 if any folder is in error state.
# SYNCTHING_API_KEY env var required.

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
```

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/dotfiles
git add hosts/thinkcentre/gatus/helper/checks/
git commit -m "Add gatus-helper health check scripts"
```

---

### Task 2: Create helper Dockerfile and HTTP server

**Files:**
- Create: `hosts/thinkcentre/gatus/helper/Dockerfile`
- Create: `hosts/thinkcentre/gatus/helper/server.sh`

- [ ] **Step 1: Create server.sh**

Create `hosts/thinkcentre/gatus/helper/server.sh`:

```sh
#!/bin/sh
# Entrypoint for gatus-helper container.
# Starts busybox httpd serving CGI scripts.

# Make all check scripts executable
chmod +x /srv/cgi-bin/*.sh

# Start httpd in foreground on port 8080
exec httpd -f -p 8080 -h /srv
```

- [ ] **Step 2: Create Dockerfile**

Create `hosts/thinkcentre/gatus/helper/Dockerfile`:

```dockerfile
FROM alpine:3.21

RUN apk add --no-cache busybox-extras coreutils curl jq

COPY server.sh /server.sh
RUN chmod +x /server.sh

COPY checks/ /srv/cgi-bin/
RUN chmod +x /srv/cgi-bin/*.sh

EXPOSE 8080

CMD ["/server.sh"]
```

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/dotfiles
git add hosts/thinkcentre/gatus/helper/Dockerfile hosts/thinkcentre/gatus/helper/server.sh
git commit -m "Add gatus-helper Dockerfile and HTTP server"
```

---

### Task 3: Create Gatus config.yaml

**Files:**
- Create: `hosts/thinkcentre/gatus/config.yaml`

- [ ] **Step 1: Create config.yaml**

Create `hosts/thinkcentre/gatus/config.yaml`:

```yaml
alerting:
  email:
    from: "status@christiantanul.com"
    host: "smtp.resend.com"
    port: 587
    username: "resend"
    password: "${RESEND_API_KEY}"
    to: "homelab@christiantanul.com"
    default-alert:
      enabled: true
      failure-threshold: 2
      success-threshold: 2
      send-on-resolved: true

storage:
  type: sqlite
  path: /data/gatus.db

ui:
  title: "Homelab Status"
  header: "Homelab Status"

# ── Infrastructure (60s) ──────────────────────────────────

endpoints:
  - name: "DNS (AdGuard 1)"
    group: "Infrastructure"
    url: "192.168.0.12"
    interval: 60s
    dns:
      query-name: "christiantanul.com"
      query-type: "A"
    conditions:
      - "[DNS_RCODE] == NOERROR"
      - "[BODY] == 192.168.0.12"
    alerts:
      - type: email

  - name: "DNS (AdGuard 2)"
    group: "Infrastructure"
    url: "100.114.162.56"
    interval: 60s
    dns:
      query-name: "christiantanul.com"
      query-type: "A"
    conditions:
      - "[DNS_RCODE] == NOERROR"
      - "[BODY] == 192.168.0.12"
    alerts:
      - type: email

  - name: "Internet"
    group: "Infrastructure"
    url: "icmp://1.1.1.1"
    interval: 60s
    conditions:
      - "[CONNECTED] == true"
    alerts:
      - type: email

  - name: "Tailscale → Synology-2"
    group: "Infrastructure"
    url: "icmp://100.114.162.56"
    interval: 60s
    conditions:
      - "[CONNECTED] == true"
    alerts:
      - type: email

  - name: "Tailscale → Proxmox"
    group: "Infrastructure"
    url: "icmp://100.122.66.112"
    interval: 60s
    conditions:
      - "[CONNECTED] == true"
    alerts:
      - type: email

  # ── ThinkCentre Health (5m) ───────────────────────────────

  - name: "Disk Space"
    group: "ThinkCentre Health"
    url: "http://gatus-helper:8080/cgi-bin/disk.sh"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "Docker Containers"
    group: "ThinkCentre Health"
    url: "http://gatus-helper:8080/cgi-bin/docker.sh"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "SMB Mounts"
    group: "ThinkCentre Health"
    url: "http://gatus-helper:8080/cgi-bin/mounts.sh"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "Syncthing Sync"
    group: "ThinkCentre Health"
    url: "http://gatus-helper:8080/cgi-bin/syncthing.sh"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  # ── ThinkCentre Services (5m) ─────────────────────────────

  - name: "AdGuard"
    group: "ThinkCentre Services"
    url: "http://adguard:80"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "AdGuard Sync"
    group: "ThinkCentre Services"
    url: "http://adguard-sync:8080"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "Home Assistant"
    group: "ThinkCentre Services"
    url: "http://home-assistant:8123"
    interval: 5m
    conditions:
      - "[STATUS] == any(200, 401)"
    alerts:
      - type: email

  - name: "Vaultwarden"
    group: "ThinkCentre Services"
    url: "http://vaultwarden:80"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "Umami"
    group: "ThinkCentre Services"
    url: "http://umami:3000"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "Obsidian CouchDB"
    group: "ThinkCentre Services"
    url: "http://obsidian-couchdb:5984"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "Plex"
    group: "ThinkCentre Services"
    url: "http://192.168.0.12:32400/web"
    interval: 5m
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "Cockpit"
    group: "ThinkCentre Services"
    url: "http://192.168.0.12:9090"
    interval: 5m
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "Healthclaw"
    group: "ThinkCentre Services"
    url: "http://healthclaw:8099"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "SpacetimeDB"
    group: "ThinkCentre Services"
    url: "http://spacetimedb:3000"
    interval: 5m
    conditions:
      - "[STATUS] == any(200, 301, 302, 404)"
    alerts:
      - type: email

  - name: "OpenClaw"
    group: "ThinkCentre Services"
    url: "http://openclaw:18789"
    interval: 5m
    conditions:
      - "[STATUS] == any(200, 301, 302, 404)"
    alerts:
      - type: email

  - name: "OpenClaw Legal"
    group: "ThinkCentre Services"
    url: "http://openclaw-legal:18790"
    interval: 5m
    conditions:
      - "[STATUS] == any(200, 301, 302, 404)"
    alerts:
      - type: email

  # ── Public Sites (5m) ─────────────────────────────────────

  - name: "christiantanul.com"
    group: "Public Sites"
    url: "https://christiantanul.com"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "intreabalegea.ro"
    group: "Public Sites"
    url: "https://intreabalegea.ro"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "staging.intreabalegea.ro"
    group: "Public Sites"
    url: "https://staging.intreabalegea.ro"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "Roast Roulette"
    group: "Public Sites"
    url: "https://roastroulette.christiantanul.com"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "Analytics (Umami)"
    group: "Public Sites"
    url: "https://analytics.christiantanul.com"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "Analytics (Plausible)"
    group: "Public Sites"
    url: "https://analytics.intreabalegea.ro"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "Bad Apple"
    group: "Public Sites"
    url: "https://bad-apple.christiantanul.com"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "Clinical Trials Scout"
    group: "Public Sites"
    url: "https://clinical-trials-scout.alexandrutanul.com"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "game.razvanaga.com"
    group: "Public Sites"
    url: "https://game.razvanaga.com"
    interval: 5m
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "Game (Hyperspace)"
    group: "Public Sites"
    url: "https://game.christiantanul.com"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "Gitea"
    group: "Public Sites"
    url: "https://gitea.christiantanul.com"
    interval: 5m
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  - name: "Dosar"
    group: "Public Sites"
    url: "https://dosar.christiantanul.com"
    interval: 5m
    conditions:
      - "[STATUS] == 401"
    alerts:
      - type: email

  # ── Synology DS923+ (5m) ──────────────────────────────────

  - name: "Synology Ping"
    group: "Synology"
    url: "icmp://192.168.0.14"
    interval: 5m
    conditions:
      - "[CONNECTED] == true"
    alerts:
      - type: email

  - name: "DSM"
    group: "Synology"
    url: "http://192.168.0.14:5000"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "Sonarr"
    group: "Synology"
    url: "http://192.168.0.14:8989"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "Radarr"
    group: "Synology"
    url: "http://192.168.0.14:7878"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "Jellyfin"
    group: "Synology"
    url: "http://192.168.0.14:8096"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "qBittorrent"
    group: "Synology"
    url: "http://192.168.0.14:9865"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "Wakapi"
    group: "Synology"
    url: "http://192.168.0.14:3000"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "Downloads"
    group: "Synology"
    url: "http://192.168.0.14:1337"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "Photos"
    group: "Synology"
    url: "http://192.168.0.14:5080"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "Drive"
    group: "Synology"
    url: "http://192.168.0.14:10002"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "Files"
    group: "Synology"
    url: "http://192.168.0.14:7000"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "Calendar"
    group: "Synology"
    url: "http://192.168.0.14:20002"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "Contacts"
    group: "Synology"
    url: "http://192.168.0.14:25555"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "Mail"
    group: "Synology"
    url: "http://192.168.0.14:21680"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "Surveillance"
    group: "Synology"
    url: "http://192.168.0.14:9900"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "VMs"
    group: "Synology"
    url: "http://192.168.0.14:14640"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  # ── Synology-2 (5m) ──────────────────────────────────────

  - name: "Synology-2 Ping"
    group: "Synology-2"
    url: "icmp://100.114.162.56"
    interval: 5m
    conditions:
      - "[CONNECTED] == true"
    alerts:
      - type: email

  - name: "DSM-2"
    group: "Synology-2"
    url: "http://100.114.162.56:5000"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email

  - name: "AdGuard-2"
    group: "Synology-2"
    url: "http://100.114.162.56:8080"
    interval: 5m
    client:
      timeout: 10s
    conditions:
      - "[STATUS] == 200"
    alerts:
      - type: email

  # ── Proxmox (5m) ─────────────────────────────────────────

  - name: "Proxmox"
    group: "Proxmox"
    url: "https://100.122.66.112:8006"
    interval: 5m
    client:
      timeout: 10s
      insecure: true
    conditions:
      - "[STATUS] == any(200, 301, 302)"
    alerts:
      - type: email
```

- [ ] **Step 2: Commit**

```bash
cd ~/Projects/dotfiles
git add hosts/thinkcentre/gatus/config.yaml
git commit -m "Add Gatus monitoring config with all endpoints"
```

---

### Task 4: Create docker-compose.yml

**Files:**
- Create: `hosts/thinkcentre/gatus/docker-compose.yml`

- [ ] **Step 1: Create docker-compose.yml**

Create `hosts/thinkcentre/gatus/docker-compose.yml`:

```yaml
services:
  gatus:
    image: twinproduction/gatus:latest
    container_name: gatus
    restart: unless-stopped
    expose:
      - 8080
    networks:
      - proxy
      - default
    environment:
      - RESEND_API_KEY=${RESEND_API_KEY}
    volumes:
      - ./config.yaml:/config/config.yaml:ro
      - gatus_data:/data
    cap_add:
      - NET_RAW
    depends_on:
      - gatus-helper

  gatus-helper:
    build: ./helper
    container_name: gatus-helper
    restart: unless-stopped
    expose:
      - 8080
    networks:
      - proxy
      - default
    environment:
      - SYNCTHING_API_KEY=${SYNCTHING_API_KEY}
      - DOCKER_HOST=unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /:/hostfs:ro

volumes:
  gatus_data:

networks:
  proxy:
    external: true
```

Key decisions:
- `cap_add: NET_RAW` lets Gatus send ICMP pings from inside the container.
- Helper gets Docker socket (read-only) for container health checks.
- Helper gets `/` mounted at `/hostfs` (read-only) for disk and mount checks.
- Both containers on `proxy` network to reach other containers by name.
- Gatus gets `RESEND_API_KEY` env var for email alerting config interpolation.

- [ ] **Step 2: Commit**

```bash
cd ~/Projects/dotfiles
git add hosts/thinkcentre/gatus/docker-compose.yml
git commit -m "Add Gatus docker-compose with helper container"
```

---

### Task 5: Add Caddy entry and update Caddyfile

**Files:**
- Modify: `hosts/thinkcentre/caddy/Caddyfile` (add `status.christiantanul.com` block)

- [ ] **Step 1: Add Caddy block**

Add this block in the `# LAN-only` section of `hosts/thinkcentre/caddy/Caddyfile`, after the `adguard-2` block:

```
status.christiantanul.com {
    import cf-tls
    import lan-only
    reverse_proxy gatus:8080
}
```

- [ ] **Step 2: Commit**

```bash
cd ~/Projects/dotfiles
git add hosts/thinkcentre/caddy/Caddyfile
git commit -m "Add status.christiantanul.com Caddy entry for Gatus"
```

---

### Task 6: Create .env, deploy, and verify

**Files:**
- Create (on thinkcentre only, not in git): `hosts/thinkcentre/gatus/.env`

**Prerequisites:** User must have:
- A Resend account with `christiantanul.com` domain verified
- A Resend API key

- [ ] **Step 1: Create .env on thinkcentre**

SSH into thinkcentre and create the file:

```bash
ssh thinkcentre 'cat > ~/Projects/dotfiles/hosts/thinkcentre/gatus/.env << EOF
RESEND_API_KEY=re_YOUR_RESEND_API_KEY
SYNCTHING_API_KEY=69cQ9YNP6DUzF2ChnTm6CVKKyrrKSMrZ
EOF'
```

Replace `re_YOUR_RESEND_API_KEY` with the actual Resend API key.

- [ ] **Step 2: Build and start the containers**

```bash
ssh thinkcentre 'cd ~/Projects/dotfiles/hosts/thinkcentre/gatus && docker compose up -d --build'
```

Expected: Both `gatus` and `gatus-helper` containers start.

- [ ] **Step 3: Verify helper is responding**

```bash
ssh thinkcentre 'docker exec gatus wget -qO- http://gatus-helper:8080/cgi-bin/disk.sh'
```

Expected: JSON response with `"status":"healthy"` and mount usage data.

- [ ] **Step 4: Reload Caddy to pick up new status subdomain**

```bash
ssh thinkcentre 'cd ~/Projects/dotfiles/hosts/thinkcentre/caddy && docker compose restart caddy'
```

- [ ] **Step 5: Verify Gatus dashboard is accessible**

```bash
ssh thinkcentre 'curl -sSL -o /dev/null -w "%{http_code}" --resolve status.christiantanul.com:443:127.0.0.1 https://status.christiantanul.com'
```

Expected: `200`

- [ ] **Step 6: Verify email alerting**

Check the Gatus dashboard at `status.christiantanul.com`. The Synology endpoints (192.168.0.14) will immediately show as failing since the Synology is currently down. After 2 consecutive failures (~10 minutes), an email alert should arrive at `homelab@christiantanul.com`.

- [ ] **Step 7: Verify all helper endpoints**

```bash
ssh thinkcentre 'for ep in disk docker mounts syncthing; do echo "=== $ep ==="; docker exec gatus wget -qO- http://gatus-helper:8080/cgi-bin/${ep}.sh; echo; done'
```

Expected: All return JSON with `"status":"healthy"` (mounts may show unhealthy if Synology SMB is down, which is expected right now).

- [ ] **Step 8: Final commit with all files**

```bash
cd ~/Projects/dotfiles
git add -A hosts/thinkcentre/gatus/ hosts/thinkcentre/caddy/Caddyfile docs/
git commit -m "Deploy Gatus monitoring for homelab"
git push
```
