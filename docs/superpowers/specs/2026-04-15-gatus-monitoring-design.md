# Gatus Monitoring for Homelab

## Overview

Self-hosted monitoring with Gatus on the ThinkCentre. Monitors all homelab services, infrastructure health, and system resources. Sends email alerts via Resend when things break.

Future migration path: move Gatus to the Pi once it's properly set up, giving off-site monitoring of the entire home network.

## Deployment

- **Location:** ThinkCentre, Docker container
- **Directory:** `hosts/thinkcentre/gatus/`
- **Dashboard:** `status.christiantanul.com` (lan-only, behind Caddy)
- **Alerts:** Email via Resend SMTP, from `status@christiantanul.com` to `homelab@christiantanul.com`

## Architecture

Two containers:

### 1. `gatus` (main)
The official `twinproduction/gatus` image. Reads `config.yaml` for endpoint definitions and alerting rules. Exposes port 8080 for the dashboard.

### 2. `gatus-helper`
Lightweight Alpine container that exposes HTTP endpoints for system-level checks that Gatus can't do natively. Runs a minimal shell-based HTTP server (busybox httpd or netcat loop).

Each endpoint returns:
- `200` + JSON body when healthy
- `503` + JSON body with details when unhealthy

Endpoints:
- `GET /disk` — disk usage for `/`, `/home`, `/mnt/nas/media`, `/mnt/nas/media_server`, `/mnt/nas/homes`
- `GET /docker` — lists containers that are stopped or unhealthy (queries Docker socket)
- `GET /mounts` — verifies SMB mounts are accessible (stat test on each mount point)
- `GET /syncthing` — queries Syncthing REST API for folder sync status (error/idle/syncing)

The helper container needs:
- Docker socket mounted (read-only) for container health checks
- Host network or access to host for Syncthing API
- Access to host filesystem mount points for disk/mount checks

## Monitored Endpoints

### Infrastructure (every 60s)

| Check | Method | Target | Success Criteria |
|-------|--------|--------|-----------------|
| DNS resolution | DNS query | AdGuard at 192.168.0.12:53 for `christiantanul.com` | Resolves to `192.168.0.12` |
| DNS correctness (AdGuard 2) | DNS query | AdGuard 2 at 100.114.162.56:53 for `christiantanul.com` | Resolves to `192.168.0.12` |
| Internet connectivity | ICMP | `1.1.1.1` | Responds |
| Tailscale to Synology-2 | ICMP | `100.114.162.56` | Responds |
| Tailscale to Proxmox | ICMP | `100.122.66.112` | Responds |

### ThinkCentre Health (every 5m)

| Check | Method | Target | Success Criteria |
|-------|--------|--------|-----------------|
| Disk space | HTTP | `gatus-helper:8080/disk` | All mounts below 85% |
| Docker health | HTTP | `gatus-helper:8080/docker` | No unhealthy/stopped containers |
| SMB mounts | HTTP | `gatus-helper:8080/mounts` | All mount points accessible |
| Syncthing sync | HTTP | `gatus-helper:8080/syncthing` | All folders idle or syncing (not errored) |

### ThinkCentre Services (every 5m, HTTP via Docker network)

| Service | URL | Success |
|---------|-----|---------|
| AdGuard | `http://adguard:80` | 200 |
| AdGuard Sync | `http://adguard-sync:8080` | 200 |
| Home Assistant | `http://home-assistant:8123` | 200 |
| Vaultwarden | `http://vaultwarden:80` | 200 |
| Umami | `http://umami:3000` | 200 |
| Obsidian CouchDB | `http://obsidian-couchdb:5984` | 200 |
| Plex | `http://192.168.0.12:32400/web` | 200 |
| Cockpit | `http://192.168.0.12:9090` | 200 |
| Healthclaw | `http://healthclaw:8099` | 200 |
| SpacetimeDB | `http://spacetimedb:3000` | 200 |
| OpenClaw | `http://openclaw:18789` | 200 |
| OpenClaw Legal | `http://openclaw-legal:18790` | 200 |

### Public Sites (every 5m, external HTTP)

| Site | URL | Success |
|------|-----|---------|
| christiantanul.com | `https://christiantanul.com` | 200 |
| intreabalegea.ro | `https://intreabalegea.ro` | 200 |
| staging.intreabalegea.ro | `https://staging.intreabalegea.ro` | 200 |
| roastroulette | `https://roastroulette.christiantanul.com` | 200 |
| analytics (umami) | `https://analytics.christiantanul.com` | 200 |
| analytics (plausible) | `https://analytics.intreabalegea.ro` | 200 |
| bad-apple | `https://bad-apple.christiantanul.com` | 200 |
| clinical-trials-scout | `https://clinical-trials-scout.alexandrutanul.com` | 200 |
| game.razvanaga.com | `https://game.razvanaga.com` | 200 |
| game.christiantanul.com | `https://game.christiantanul.com` | 200 |
| gitea | `https://gitea.christiantanul.com` | 200 |
| dosar | `https://dosar.christiantanul.com` | 401 (basic auth) |

### Synology DS923+ (every 5m, 192.168.0.14)

| Service | Method | Target | Success |
|---------|--------|--------|---------|
| Ping | ICMP | `192.168.0.14` | Responds |
| DSM | HTTP | `http://192.168.0.14:5000` | 200 |
| Sonarr | HTTP | `http://192.168.0.14:8989` | 200 |
| Radarr | HTTP | `http://192.168.0.14:7878` | 200 |
| Jellyfin | HTTP | `http://192.168.0.14:8096` | 200 |
| qBittorrent | HTTP | `http://192.168.0.14:9865` | 200 |
| Wakapi | HTTP | `http://192.168.0.14:3000` | 200 |
| Downloads | HTTP | `http://192.168.0.14:1337` | 200 |
| Photos | HTTP | `http://192.168.0.14:5080` | 200 |
| Drive | HTTP | `http://192.168.0.14:10002` | 200 |
| Files | HTTP | `http://192.168.0.14:7000` | 200 |
| Calendar | HTTP | `http://192.168.0.14:20002` | 200 |
| Contacts | HTTP | `http://192.168.0.14:25555` | 200 |
| Mail | HTTP | `http://192.168.0.14:21680` | 200 |
| Surveillance | HTTP | `http://192.168.0.14:9900` | 200 |
| VMs | HTTP | `http://192.168.0.14:14640` | 200 |

### Synology-2 (every 5m, 100.114.162.56 via Tailscale)

| Service | Method | Target | Success |
|---------|--------|--------|---------|
| Ping | ICMP | `100.114.162.56` | Responds |
| DSM-2 | HTTP | `http://100.114.162.56:5000` | 200 |
| AdGuard-2 | HTTP | `http://100.114.162.56:8080` | 200 |

### Proxmox (every 5m, 100.122.66.112 via Tailscale)

| Service | Method | Target | Success |
|---------|--------|--------|---------|
| Proxmox UI | HTTPS | `https://100.122.66.112:8006` | 200 (skip TLS verify) |

## Alert Rules

- **Threshold:** Alert after 2 consecutive failures
- **Disk space:** Alert when any mount exceeds 85% usage
- **Recovery:** Send recovery notification when service comes back
- **Provider:** Resend SMTP (`smtp.resend.com:587`)

## File Structure

```
hosts/thinkcentre/gatus/
├── docker-compose.yml
├── config.yaml
├── helper/
│   ├── Dockerfile
│   ├── server.sh          (busybox httpd entrypoint + CGI routing)
│   └── checks/
│       ├── disk.sh
│       ├── docker.sh
│       ├── mounts.sh
│       └── syncthing.sh
└── .env                   (RESEND_API_KEY, SYNCTHING_API_KEY)
```

## Docker Networking

Both `gatus` and `gatus-helper` join the existing `proxy` network so they can reach other containers by name. The helper also needs:
- Docker socket: `/var/run/docker.sock:/var/run/docker.sock:ro`
- Host mounts: bind-mount `/mnt/nas` read-only for mount checks
- Host filesystem: bind-mount `/` at `/hostfs` read-only for disk checks

Gatus needs no special mounts beyond its config file.

## Caddy Entry

```
status.christiantanul.com {
    import cf-tls
    import lan-only
    reverse_proxy gatus:8080
}
```

## Dependencies

- Resend account with `christiantanul.com` domain verified
- Resend API key (stored in `.env`, ignored by Syncthing via existing `.stignore` rule)
- Syncthing API key from ThinkCentre (already in Syncthing config)
