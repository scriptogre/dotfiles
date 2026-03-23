# Pi → ThinkCentre Migration Plan

## Context

Migrating all services from Raspberry Pi (192.168.0.41) to ThinkCentre (192.168.0.12).
ThinkCentre runs NixOS managed via flakes at `~/dotfiles/hosts/thinkcentre/`.
Services run as docker-compose projects in `~/service-name/` directories.
Docker-compose.yml files are version-controlled in `dotfiles/hosts/thinkcentre/<service>/`
and auto-discovered + symlinked into ~/ by home-manager.

## Completed

### Nix Config
- [x] NAS mounts, firewall ports, system packages
- [x] home-manager with auto-discovery of docker-compose.yml files (no manual listing)
- [x] Extracted `gaming-vm.nix` module (VFIO, libvirt, GPU passthrough hook, cockpit-machines)
- [x] Cockpit web UI in flake.nix with libvirt-dbus
- [x] Syncthing as native NixOS service (not container)
- [x] Justfile as separate file (not inline Nix string)
- [x] NixOS rebuild succeeded

### Services Running on ThinkCentre
- [x] caddy (custom build with Cloudflare DNS plugin)
- [x] adguard (+ sync + monitor)
- [x] openclaw + healthclaw
- [x] home-assistant (+ speech-to-phrase)
- [x] umami (+ postgres, DB imported from Pi)
- [x] vaultwarden
- [x] gitea-mirror-sync (token needs updating)
- [x] iSponsorBlockTV
- [x] plex (host networking)
- [x] hyperspace/spacetimedb
- [x] syncthing (native NixOS service)

### App Repos Cloned & Building
- [x] intreaba-legea-staging (+ production via docker-compose.production.yml)
- [x] roast-roulette
- [x] bad-apple
- [x] clinical-trials-scout
- [x] algo
- [x] gocost-web
- [x] browser-test

### Data Synced
- [x] All dotfiles service data (caddy, adguard, openclaw, home-assistant, vaultwarden, gitea-mirror-sync, iSponsorBlockTV)
- [x] umami DB (pg_dump + import)
- [x] syncthing config (~/.config/syncthing)
- [x] roast-roulette media volume
- [x] intreaba-legea staging + production DB exports
- [x] clinical-trials-scout DB exports (main + drugcentral)

### Caddyfile Updated
- [x] `thinkcentre:*` → `localhost:*` (Plex, Cockpit, SpacetimeDB)
- [x] Removed grafana, n8n blocks
- [x] Reorganized sections (removed Pi references)

### Removed Services
- n8n (no longer used)
- rotki (no longer used)
- grafana (no longer used)

## What Still Needs to Be Done

### App-Specific Fixes
- [ ] roast-roulette — migration error on `development` branch (KeyError: 'is_approved')
- [ ] gitea-mirror-sync — generate new Gitea API token and update .env
- [ ] intreaba-legea — Anthropic API credits need topping up
- [ ] Commit dotfiles changes and push to GitHub/Gitea

### Future: Container Registry
App repos (intreaba-legea, roast-roulette, bad-apple, clinical-trials-scout, algo) currently
live as git clones in `~/Projects/` on the ThinkCentre with source code on the server.
This should be replaced with:
- Push built images to Gitea container registry from CI/CD
- docker-compose files in dotfiles reference images (no source code on server)
- Eliminates: git clones on server, build dependencies, stale lockfiles, architecture mismatches

### Stop Services on Pi
- [ ] Stop all containers on Pi
- [ ] Keep Pi running for SSH access / fallback

## Architecture (Current State)

```
ThinkCentre (192.168.0.12) - NixOS
├── ~/dotfiles/                          # Nix config (git repo)
│   └── hosts/thinkcentre/
│       ├── flake.nix                    # System config (auto-discovers services)
│       ├── gaming-vm.nix               # GPU passthrough, libvirt, VFIO
│       ├── Justfile                    # Task runner commands
│       ├── caddy/                      # Reverse proxy (ports 80/443)
│       ├── adguard/                    # DNS (port 53)
│       ├── openclaw/                   # AI assistant + healthclaw
│       ├── home-assistant/             # Smart home (port 8123)
│       ├── umami/                      # Web analytics
│       ├── vaultwarden/                # Password manager
│       ├── hyperspace/                 # SpacetimeDB game (port 3000)
│       ├── gitea-mirror-sync/          # GitHub → Gitea mirror
│       ├── iSponsorBlockTV/            # YouTube ad blocking
│       └── plex/                       # Media server (port 32400)
├── ~/intreaba-legea-staging/            # App (git clone, runs staging + production)
├── ~/roast-roulette/                    # App (git clone)
├── ~/bad-apple/                         # App (git clone)
├── ~/clinical-trials-scout/             # App (git clone)
├── ~/algo/                              # Trading bot (git clone)
├── ~/gocost-web/                        # Cost tracker (git clone)
└── ~/browser-test/                      # App (git clone)

Native NixOS services: syncthing, tailscale, cockpit, openssh

Raspberry Pi (192.168.0.41) - to be decommissioned
└── (all services still running as fallback)
```

## Key Decisions
- Docker-compose in ~/ directories for portability
- docker-compose.yml files auto-discovered by home-manager (drop a folder = new service)
- Syncthing runs as native NixOS service (needs filesystem access)
- GPU passthrough logic isolated in gaming-vm.nix module
- Caddy uses localhost/container names for upstreams (no DNS dependency)
- .env files NOT in git - only .env.example templates
- `restart: unless-stopped` on all services handles auto-start on boot
