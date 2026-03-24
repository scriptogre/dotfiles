# ThinkCentre Architecture v2

## Problem

The current ThinkCentre homelab setup has too many layers of indirection:

- Two copies of dotfiles (`~/dotfiles` git clone + `~/Projects/dotfiles` via Syncthing)
- `just link` creates symlinks from `~/service` to `~/dotfiles/hosts/thinkcentre/service/`
- A Gitea webhook auto-pulls changes and runs `just link`
- .env files get lost/wiped due to path confusion between the two copies
- Bind-mounted source code in production means filesystem changes can break running services

## Design

### Core Principle

`~/Projects/` (Syncthing'd from Mac) is the single source of truth. No clones, no symlinks, no webhook. No git management on ThinkCentre.

### Directory Layout

```
~/
  Justfile     -> Projects/dotfiles/hosts/thinkcentre/Justfile
  README.md    -> Projects/dotfiles/hosts/thinkcentre/README.md
  Projects/                                          <- Syncthing from Mac
    dotfiles/hosts/thinkcentre/                      <- infra services + NixOS config
      caddy/docker-compose.yml
      adguard/docker-compose.yml
      openclaw/docker-compose.yml
      home-assistant/docker-compose.yml
      hyperspace/docker-compose.yml                  <- SpacetimeDB infra, NOT the game source
      plex/docker-compose.yml
      vaultwarden/docker-compose.yml
      umami/docker-compose.yml
      iSponsorBlockTV/docker-compose.yml
      flake.nix
      Justfile
    roast-roulette/docker-compose.production.yml     <- user's projects
    hyperspace/                                      <- game source code (separate from infra)
    ...
```

Note: `hyperspace/` appears in both places because they are different things:
- `dotfiles/hosts/thinkcentre/hyperspace/` = SpacetimeDB server deployment (infra)
- `~/Projects/hyperspace/` = game client/module source code (project)

CDPATH checks thinkcentre first, so `cd hyperspace` goes to the infra service. Use `cd ~/Projects/hyperspace` for the source.

### Shell Navigation (CDPATH)

```bash
CDPATH=".:$HOME/Projects/dotfiles/hosts/thinkcentre:$HOME/Projects"
```

Managed via home-manager in the NixOS flake. Resolution order:

1. Current directory
2. `~/Projects/dotfiles/hosts/thinkcentre/` (infra services)
3. `~/Projects/` (user's projects)

`cd caddy` finds the infra service. `cd roast-roulette` finds the project. Adding a new service or project requires zero config changes.

### Data Storage: Named Volumes

Service data uses Docker named volumes instead of bind-mounted host directories where possible.

**Migrate to named volumes:**
- `caddy`: `./data:/data` and `./config:/config`
- `adguard`: `./config` and `./work`
- `plex`: `./config:/config`
- `home-assistant`: `./config:/config`
- `vaultwarden`: `./vw-data:/data`
- `iSponsorBlockTV`: `./data:/app/data`
- `umami`: database data
- `hyperspace`: `./data:/stdb` (SpacetimeDB state)

**Keep as bind mounts (host/NAS paths):**
- `plex`: `/mnt/nas/media:/data/media:ro` (NAS mount, cannot be a named volume)
- `home-assistant`: any NAS mounts
- `openclaw`: `./config`, `./workspace`, `./healthclaw/data` (these are checked into git and should remain visible/editable in the repo)
- `openclaw`: `./ssh:/home/node/.ssh:ro` (SSH keys, must be in repo)
- `caddy`: `./Caddyfile:/etc/caddy/Caddyfile:ro` (git-tracked config, intentionally kept as bind mount)
- `hyperspace`: `/srv/hyperspace/static` (static assets -- handle like Caddy static sites, see below)

Benefits of named volumes:
- Data stays Docker-managed, never syncs via Syncthing to Mac
- Inspectable via `docker volume inspect` and `docker exec`
- Prepares for future Docker Swarm migration

### Data Migration

Each service with bind-mounted data needs a migration step before switching to named volumes. General pattern:

```bash
# 1. Stop the service
docker compose down

# 2. Create the named volume
docker volume create <service>_data

# 3. Copy data into the volume
docker run --rm \
  -v $(pwd)/data:/source:ro \
  -v <service>_data:/dest \
  alpine cp -a /source/. /dest/

# 4. Update docker-compose.yml to use the named volume

# 5. Start the service
docker compose up -d
```

Critical services (migrate with extra care):
- **vaultwarden**: password vault data -- back up first
- **home-assistant**: automations, integrations, history DB
- **plex**: library metadata, watch history
- **adguard**: DNS config, block lists

### Production Containers: Self-Contained Images

No bind-mounting source code in production compose files. Code is baked into images via multi-stage Dockerfiles.

- `docker-compose.production.yml`: references built images, no source bind mounts
- `docker-compose.local.yml`: bind mounts for dev hot-reload

This means renaming or refactoring a project folder on Mac does not break running services on ThinkCentre. A service only updates when explicitly rebuilt and redeployed.

**Static sites served by Caddy** (christiantanul.com, game.christiantanul.com):

Currently Caddy bind-mounts `/home/chris/website/dist` and `/home/chris/game/web`. These are static HTML/CSS/JS files, not application servers. Options:

1. **Bake into Caddy image** via multi-stage build (copy static files into Caddy's Dockerfile)
2. **Named volume populated by a build/deploy step** (build project, copy output into volume)
3. **Keep bind mounts** pointing to `~/Projects/website/dist` and `~/Projects/game/web`

Recommended: option 2 (named volume). Build the project, populate the volume, Caddy serves from it. Decouples serving from the filesystem. Note: `dist/` is in `.stignore` so it won't sync from Mac -- builds must happen on ThinkCentre or in CI.

### .env Handling

- `.env` files are gitignored and `.stignore`'d -- they never leave the machine they're on
- `.env.example` is checked into git as documentation (not blocked by `.stignore`)
- ThinkCentre `.env` files contain `COMPOSE_FILE=docker-compose.production.yml`
- Mac `.env` files contain `COMPOSE_FILE=docker-compose.local.yml`

### Deployment Workflow

```bash
# Infra service
cd caddy && docker compose up -d

# User's project
cd roast-roulette && docker compose up -d    # COMPOSE_FILE in .env selects production

# NixOS changes
just rebuild
```

### NixOS Flake and Git

`nixos-rebuild switch --flake <path>` requires a git repo to determine which files to evaluate. However, `.stignore` excludes `**/.git`, so git metadata does not sync from Mac.

Solution: the Justfile `rebuild` recipe initializes a throwaway git repo if needed. This repo is used solely for Nix evaluation -- never pushed, never shared. The Mac's git history is the real source of truth.

### Justfile

```just
base := home_directory() / "Projects/dotfiles/hosts/thinkcentre"

# Rebuild NixOS from flake (creates throwaway git repo for Nix evaluation)
rebuild:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{base}}
    if [ ! -d .git ]; then
      git init -q && git add -A && git commit -q -m "nix eval"
    else
      git add -A && git diff-index --quiet HEAD || git commit -q -m "nix eval"
    fi
    sudo nixos-rebuild switch --flake {{base}}
```

### .stignore Changes

The current `.stignore` starts with:
```
// Dotfiles is git-managed separately (webhook), not Syncthing
dotfiles/
```

This must be changed. Remove the `dotfiles/` exclusion so Syncthing syncs dotfiles to ThinkCentre. Add `.env` protection.

**Updated .stignore** (preserving existing patterns, adding new ones):

```
// Secrets -- must be added BEFORE removing dotfiles/ exclusion
.env

**/.git
**/node_modules
**/dist
**/.next
**/__pycache__
**/target
**/.cache
**/.ruff_cache
**/.pytest_cache
**/.mypy_cache
**/.turbo
**/.sandbox
**/.venv
**/venv
**/.idea
**/.stfolder
**/.stversions
**/*.sync-conflict-*
**/*.hm-backup

// Build artifacts
**/.build
```

Note: using `.env` (not `*.env`) to avoid catching `.env.example` files.

### NixOS Flake Changes

- Add CDPATH to shell config via home-manager (`programs.zsh.sessionVariables` or `programs.zsh.initContent`)
- Add `~/Justfile` symlink via home-manager (`home.file`)
- Add `~/README.md` symlink via home-manager (`home.file`)

### Docker Prerequisites

The `proxy` external Docker network must exist before any service starts:

```bash
docker network create proxy
```

This should be documented in README.md. Run it once during initial setup.

### Discoverability

`ls ~` shows:

```
Justfile  -> Projects/dotfiles/hosts/thinkcentre/Justfile
README.md -> Projects/dotfiles/hosts/thinkcentre/README.md
Projects/
```

An LLM or user SSHing in can immediately:
- `cat README.md` to understand the setup
- `just rebuild` to apply NixOS changes
- `cd <service>` to navigate to any service (via CDPATH)
- `docker ps` to see running containers

Note: CDPATH only affects `cd`. Commands like `ls caddy` or `cat caddy/Caddyfile` still need a full path or you must `cd` first.

### Documentation Updates

- **README.md**: rewrite to describe v2 architecture (CDPATH, no symlinks, deployment workflow)
- **SYNCTHING.md**: update or remove -- it describes the old symlink-based architecture
- **OpenClaw AGENTS.md**: update paths (`~/Projects/dotfiles/hosts/thinkcentre/` instead of `~/service-name/`)
- **OpenClaw host-ssh/SKILL.md**: update path references and add CDPATH explanation

## What Gets Removed

- `~/dotfiles` (the git clone) -- deleted
- Gitea webhook / auto-pull mechanism
- `just link` recipe
- All `~/service` symlinks created by `just link`
- Source code bind mounts in production docker-compose files (e.g., Caddy's `/home/chris/website/dist` and `/home/chris/game/web` mounts)

## What Gets Changed

- Services with host-dir data mounts: migrate to named volumes (with per-service data migration)
- Caddy: static site serving via named volumes instead of bind mounts
- flake.nix: add CDPATH, ~/Justfile symlink, ~/README.md symlink via home-manager
- Justfile: strip down to just `rebuild` (with git-init-for-nix), remove all other recipes
- .stignore: remove `dotfiles/` exclusion, add `.env`
- OpenClaw AGENTS.md + host-ssh skill: update paths and instructions
- README.md, SYNCTHING.md: rewrite for v2

## Migration Order

This order matters -- steps have dependencies:

1. **Add `.env` to `.stignore`** -- MUST happen before step 2, or secrets will sync
2. **Remove `dotfiles/` from `.stignore`** -- enables dotfiles to sync to ThinkCentre
3. **Wait for Syncthing to fully sync** `~/Projects/dotfiles` to ThinkCentre
4. **On ThinkCentre: update Justfile** -- strip down to just `rebuild` with git-init-for-nix
5. **Create home-manager config** -- CDPATH, ~/Justfile symlink, ~/README.md symlink
6. **Run `just rebuild`** from new path -- applies NixOS + home-manager changes
7. **Migrate service data** to named volumes (one service at a time, starting with least critical)
8. **Update docker-compose.yml files** to use named volumes
9. **Handle Caddy static sites** -- set up named volumes for website/game
10. **Update OpenClaw docs** -- AGENTS.md, host-ssh skill
11. **Update README.md and SYNCTHING.md**
12. **Clean up** -- delete `~/dotfiles`, remove old symlinks, remove webhook

## Known Risks and Mitigations

1. **CDPATH name collision**: If an infra service and a project share a name (e.g., `hyperspace`), the infra service wins (checked first). Mitigation: use full path for the project when needed.

2. **Syncthing conflicts**: Editing the same file on Mac and ThinkCentre simultaneously creates `.sync-conflict-*` files. Mitigation: rare scenario; resolve with Claude Code if it happens.

3. **NixOS flake git workaround**: The throwaway git repo in the Justfile `rebuild` recipe is a hack. It works but is inelegant. If Nix ever supports `path:` flakes natively with nixos-rebuild, switch to that.

4. **Mac offline**: If Mac is off, ThinkCentre has whatever was last synced. Running containers are unaffected (images are self-contained). Only new deployments or rebuilds depend on current files.

5. **Accidental filesystem changes on Mac**: Renaming/deleting a project folder syncs to ThinkCentre. Mitigation: production containers use baked-in images, not bind-mounted source. Running services survive until explicitly redeployed.

6. **OpenClaw SSH key in repo**: `openclaw/ssh/id_ed25519` is a private key in the dotfiles repo. Now that dotfiles syncs via Syncthing, it will exist on both machines. This is acceptable since the key only grants access to the ThinkCentre itself (authorized_keys), but worth noting.

7. **Data migration risk**: Moving from bind mounts to named volumes can lose data if done incorrectly. Mitigation: back up each service's data directory before migrating. Migrate one service at a time, verify it works before proceeding.
