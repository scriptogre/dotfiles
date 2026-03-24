# ThinkCentre Architecture v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify the ThinkCentre homelab to use Syncthing as the single source of truth, eliminating symlinks, webhook, and the separate git clone.

**Architecture:** `~/Projects/` syncs from Mac via Syncthing. Infra services live in `dotfiles/hosts/thinkcentre/<service>/`, user projects in `~/Projects/<project>/`. CDPATH enables `cd <service>` from anywhere. Named volumes replace bind-mounted data dirs. Production containers are self-contained images.

**Tech Stack:** NixOS flakes, home-manager, Docker Compose, Syncthing, zsh (CDPATH)

**Spec:** `docs/superpowers/specs/2026-03-24-thinkcentre-architecture-v2-design.md`

**Important context:**
- Claude Code runs on the Mac. All file edits happen in `~/Projects/dotfiles/` on Mac.
- ThinkCentre commands (rebuild, data migration, cleanup) must be run via SSH.
- After Mac-side edits, Syncthing propagates changes to ThinkCentre automatically.
- The `proxy` Docker network already exists on ThinkCentre.

---

### Task 1: Add .env to .stignore

**CRITICAL: This MUST happen before Task 2. If .env is not ignored before dotfiles starts syncing, production secrets will propagate to the Mac.**

**Files:**
- Modify: `/Users/chris/Projects/.stignore`

- [ ] **Step 1: Add .env to .stignore**

Add `.env` as the first pattern (before any other rules). The file should become:

```
// Secrets (must come before any folder un-ignoring)
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

Note: the `dotfiles/` exclusion is removed in this same edit. The `.env` pattern MUST be present before `dotfiles/` is removed — since we're writing the whole file atomically, this is safe.

- [ ] **Step 2: Verify .stignore is correct**

```bash
cat ~/Projects/.stignore
```

Expected: `.env` is present, `dotfiles/` exclusion is gone, all other patterns preserved.

Note: `.stignore` lives at `~/Projects/.stignore`, OUTSIDE the dotfiles repo. No git commit needed — it syncs via Syncthing itself.

---

### Task 2: Verify Syncthing sync

**Files:** None (verification only)

- [ ] **Step 1: SSH to ThinkCentre and check that dotfiles appeared**

```bash
ssh thinkcentre "ls ~/Projects/dotfiles/hosts/thinkcentre/"
```

Expected: the full list of service directories (caddy, adguard, openclaw, etc.) and flake.nix.

If `~/Projects/dotfiles` doesn't exist yet, wait a minute for Syncthing to propagate. Check Syncthing UI at `https://syncthing.christiantanul.com` for sync status.

- [ ] **Step 2: Verify .env files did NOT sync**

```bash
ssh thinkcentre "find ~/Projects/dotfiles/hosts/thinkcentre -name '.env' -type f 2>/dev/null | head -5"
```

Expected: no output (no .env files synced).

- [ ] **Step 3: Verify .env files still exist on ThinkCentre's existing service dirs**

The old setup has .env files at `~/dotfiles/hosts/thinkcentre/<service>/.env` (or `~/<service>/.env` via symlinks). These are NOT affected by Syncthing since they're in the old git clone, not in `~/Projects/`.

```bash
ssh thinkcentre "ls ~/dotfiles/hosts/thinkcentre/caddy/.env ~/dotfiles/hosts/thinkcentre/openclaw/.env 2>/dev/null"
```

Expected: these files exist (they're the current production secrets).

---

### Task 3: Update Justfile

**Files:**
- Modify: `hosts/thinkcentre/Justfile`

- [ ] **Step 1: Rewrite Justfile**

Replace the entire Justfile with:

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

- [ ] **Step 2: Commit**

```bash
cd ~/Projects/dotfiles && git add hosts/thinkcentre/Justfile && git commit -m "simplify Justfile to just rebuild"
```

---

### Task 4: Update flake.nix (CDPATH + home.file symlinks)

**Files:**
- Modify: `hosts/thinkcentre/flake.nix`

- [ ] **Step 1: Add `config` to home-manager function args**

The current function signature is:

```nix
home-manager.users.chris = { pkgs, lib, ... }: {
```

Change it to:

```nix
home-manager.users.chris = { pkgs, lib, config, ... }: {
```

This is required for `mkOutOfStoreSymlink` in step 3.

- [ ] **Step 2: Add CDPATH to home-manager zsh config**

In the `home-manager.users.chris` block (after the `dconf.settings`), add:

```nix
programs.zsh.initContent = lib.mkAfter ''
  export CDPATH=".:$HOME/Projects/dotfiles/hosts/thinkcentre:$HOME/Projects"
'';
```

Make sure to include a 1-2 line super clear, concise, and simple comment of why this is done.

Using `initContent` with `mkAfter` ensures it runs after the common zshrc (loaded via `common/home.nix`).

- [ ] **Step 3: Add ~/Justfile and ~/README.md symlinks**

In the same `home-manager.users.chris` block, add:

```nix
home.file."Justfile".source = config.lib.file.mkOutOfStoreSymlink "/home/chris/Projects/dotfiles/hosts/thinkcentre/Justfile";
home.file."README.md".source = config.lib.file.mkOutOfStoreSymlink "/home/chris/Projects/dotfiles/hosts/thinkcentre/README.md";
```

`mkOutOfStoreSymlink` creates a symlink directly to the path on disk (not the Nix store), so changes are visible without a rebuild.

```nix
home-manager.users.chris = { pkgs, lib, config, ... }: {
```

(Add `config` if missing.)

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/dotfiles && git add hosts/thinkcentre/flake.nix && git commit -m "add CDPATH and home symlinks for architecture v2"
```

---

### Task 5: Run NixOS rebuild on ThinkCentre

**Files:** None (ThinkCentre SSH command)

- [ ] **Step 1: Wait for Syncthing to propagate Tasks 3-4**

```bash
ssh thinkcentre "cat ~/Projects/dotfiles/hosts/thinkcentre/Justfile | head -5"
```

Expected: shows the new Justfile with `base := home_directory() / "Projects/dotfiles/hosts/thinkcentre"`.

- [ ] **Step 2: Run rebuild from the new path**

```bash
ssh thinkcentre "cd ~/Projects/dotfiles/hosts/thinkcentre && just rebuild"
```

This will:
1. Create a throwaway git repo in `~/Projects/dotfiles/hosts/thinkcentre/` (since `**/.git` is .stignore'd, this won't sync back)
2. Run `nixos-rebuild switch`
3. Apply CDPATH to chris's zsh shell
4. Create `~/Justfile` and `~/README.md` symlinks

Expected: rebuild succeeds. If it fails, check error output — common issues:
- Missing `config` in function args (step 4.2)
- File conflicts with existing `~/Justfile` symlink (the `backupFileExtension = "hm-backup"` setting should handle this)

- [ ] **Step 3: Verify CDPATH works**

```bash
ssh thinkcentre "zsh -l -c 'cd caddy && pwd'"
```

Expected: `/home/chris/Projects/dotfiles/hosts/thinkcentre/caddy`

- [ ] **Step 4: Verify home symlinks**

```bash
ssh thinkcentre "ls -la ~/Justfile ~/README.md"
```

Expected: symlinks pointing to `Projects/dotfiles/hosts/thinkcentre/Justfile` and `README.md`.

---

### Task 6: Copy .env files to new paths

**CRITICAL: Services currently run from `~/dotfiles/hosts/thinkcentre/<service>/` (the old git clone). The new paths are `~/Projects/dotfiles/hosts/thinkcentre/<service>/`. Production .env files must be copied to the new locations before switching services.**

**Files:** None (ThinkCentre SSH commands)

- [ ] **Step 1: List all existing .env files**

```bash
ssh thinkcentre "find ~/dotfiles/hosts/thinkcentre -name '.env' -type f"
```

- [ ] **Step 2: Copy each .env file to the new path**

```bash
ssh thinkcentre 'for f in $(find ~/dotfiles/hosts/thinkcentre -name ".env" -type f); do
  rel="${f#$HOME/dotfiles/}"
  dest="$HOME/Projects/dotfiles/$rel"
  if [ ! -f "$dest" ]; then
    cp "$f" "$dest"
    echo "copied: $rel"
  else
    echo "exists: $rel"
  fi
done'
```

- [ ] **Step 3: Verify critical .env files exist at new paths**

```bash
ssh thinkcentre "ls -la ~/Projects/dotfiles/hosts/thinkcentre/{caddy,openclaw,adguard}/.env"
```

Expected: all three files exist with non-zero size.

---

### Task 7: Migrate service data to named volumes

**This is the most delicate task. Each service is migrated individually. Back up before each migration. Start with least critical services.**

**Files:**
- Modify: `hosts/thinkcentre/iSponsorBlockTV/docker-compose.yml`
- Modify: `hosts/thinkcentre/hyperspace/docker-compose.yml`
- Modify: `hosts/thinkcentre/adguard/docker-compose.yml`
- Modify: `hosts/thinkcentre/caddy/docker-compose.yml`
- Modify: `hosts/thinkcentre/vaultwarden/docker-compose.yml`
- Modify: `hosts/thinkcentre/plex/docker-compose.yml`
- Modify: `hosts/thinkcentre/home-assistant/docker-compose.yml`

**Note:** umami already uses a named volume (`umami-db-data`) — no migration needed.

**IMPORTANT: Data directories (./config, ./data, etc.) exist on the OLD paths (`~/dotfiles/hosts/thinkcentre/<service>/`) — NOT on the Syncthing'd new paths. All `docker run` migration commands must reference the OLD paths.**

**Migration order (least critical first):**

#### 7a: iSponsorBlockTV

- [ ] **Step 1: Back up and verify .env**

```bash
ssh thinkcentre 'cd ~/dotfiles/hosts/thinkcentre/iSponsorBlockTV && \
  [ -d data ] && tar czf ~/isponsorblocktv-backup-$(date +%Y%m%d).tar.gz data && \
  echo "backed up"'
```

- [ ] **Step 2: Update docker-compose.yml (on Mac)**

Change:
```yaml
    volumes:
      - ./data:/app/data
```
To:
```yaml
    volumes:
      - isponsorblocktv_data:/app/data

volumes:
  isponsorblocktv_data:
```

- [ ] **Step 3: Wait for Syncthing sync, then migrate data on ThinkCentre**

First verify the updated compose file synced:
```bash
ssh thinkcentre "grep isponsorblocktv_data ~/Projects/dotfiles/hosts/thinkcentre/iSponsorBlockTV/docker-compose.yml"
```

Then migrate (note: data lives under OLD path `~/dotfiles/...`):
```bash
ssh thinkcentre 'OLD=~/dotfiles/hosts/thinkcentre/iSponsorBlockTV && \
  NEW=~/Projects/dotfiles/hosts/thinkcentre/iSponsorBlockTV && \
  docker compose -f $OLD/docker-compose.yml down && \
  docker volume create isponsorblocktv_data && \
  docker run --rm -v $OLD/data:/source:ro -v isponsorblocktv_data:/dest alpine cp -a /source/. /dest/ && \
  cd $NEW && docker compose up -d && \
  echo "done"'
```

- [ ] **Step 4: Verify container is running**

```bash
ssh thinkcentre "docker ps --filter name=isponsorblocktv --format '{{.Status}}'"
```

Expected: "Up" status.

#### 7b: hyperspace (SpacetimeDB)

- [ ] **Step 1: Update docker-compose.yml**

Change:
```yaml
    volumes:
      - ./data:/stdb
      - /srv/hyperspace/static:/srv/hyperspace/static:ro
```
To:
```yaml
    volumes:
      - hyperspace_stdb:/stdb
      - hyperspace_static:/srv/hyperspace/static:ro

volumes:
  hyperspace_stdb:
  hyperspace_static:
```

- [ ] **Step 1.5: Back up hyperspace data**

```bash
ssh thinkcentre 'cd ~/dotfiles/hosts/thinkcentre/hyperspace && \
  [ -d data ] && tar czf ~/hyperspace-backup-$(date +%Y%m%d).tar.gz data && echo "backed up"'
```

- [ ] **Step 2: Wait for sync, then migrate data on ThinkCentre**

```bash
ssh thinkcentre 'OLD=~/dotfiles/hosts/thinkcentre/hyperspace && \
  NEW=~/Projects/dotfiles/hosts/thinkcentre/hyperspace && \
  docker compose -f $OLD/docker-compose.yml down && \
  docker volume create hyperspace_stdb && \
  docker run --rm -v $OLD/data:/source:ro -v hyperspace_stdb:/dest alpine cp -a /source/. /dest/ && \
  cd $NEW && docker compose up -d'
```

Note: `hyperspace_static` starts empty. It needs to be populated by a build/deploy step. **TODO: create a deploy script or Justfile recipe for populating static site volumes (website_dist, game_web, hyperspace_static).**

#### 7c: adguard

- [ ] **Step 1: Back up adguard config on ThinkCentre**

```bash
ssh thinkcentre 'cd ~/dotfiles/hosts/thinkcentre/adguard && \
  tar czf ~/adguard-backup-$(date +%Y%m%d).tar.gz config work'
```

- [ ] **Step 2: Update docker-compose.yml**

Change the adguard service volumes:
```yaml
    volumes:
      - ./config:/opt/adguardhome/conf
      - ./work:/opt/adguardhome/work
```
To:
```yaml
    volumes:
      - adguard_conf:/opt/adguardhome/conf
      - adguard_work:/opt/adguardhome/work
```

Also note: the `adguard-monitor` service mounts `./run_monitor.sh:/run_monitor.sh:ro` but this file doesn't exist in the repo. Either create a placeholder or remove the adguard-monitor service if it's not needed. **Ask the user which they prefer.**

Add volumes section:
```yaml
volumes:
  adguard_conf:
  adguard_work:
```

- [ ] **Step 3: Wait for sync, then migrate data on ThinkCentre**

```bash
ssh thinkcentre 'OLD=~/dotfiles/hosts/thinkcentre/adguard && \
  NEW=~/Projects/dotfiles/hosts/thinkcentre/adguard && \
  docker compose -f $OLD/docker-compose.yml down && \
  docker volume create adguard_conf && \
  docker volume create adguard_work && \
  docker run --rm -v $OLD/config:/source:ro -v adguard_conf:/dest alpine cp -a /source/. /dest/ && \
  docker run --rm -v $OLD/work:/source:ro -v adguard_work:/dest alpine cp -a /source/. /dest/ && \
  [ -f $NEW/.env ] || cp $OLD/.env $NEW/.env && \
  cd $NEW && docker compose up -d'
```

- [ ] **Step 4: Verify DNS still resolves**

```bash
ssh thinkcentre "dig @127.0.0.1 google.com +short"
```

Expected: IP addresses returned.

#### 7d: caddy

- [ ] **Step 1: Back up caddy data**

```bash
ssh thinkcentre 'cd ~/dotfiles/hosts/thinkcentre/caddy && \
  tar czf ~/caddy-backup-$(date +%Y%m%d).tar.gz data config'
```

- [ ] **Step 2: Update docker-compose.yml**

The Caddy compose file needs several changes:
1. `./data:/data` and `./config:/config` become named volumes
2. Remove `/home/chris/website/dist:/srv/website:ro` and `/home/chris/game/web:/srv/game:ro` bind mounts
3. Add named volumes for static sites
4. Keep `./Caddyfile:/etc/caddy/Caddyfile:ro` (git-tracked config)
5. Keep `roast-roulette_media` external volume

Updated docker-compose.yml:

```yaml
services:
  caddy:
    build: .
    container_name: caddy
    command: caddy run --config /etc/caddy/Caddyfile --adapter caddyfile --watch
    environment:
      - CLOUDFLARE_API_TOKEN
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - caddy_data:/data
      - caddy_config:/config
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - roast-roulette_media:/srv/media/django:ro
      - website_dist:/srv/website:ro
      - game_web:/srv/game:ro
    restart: always

volumes:
  caddy_data:
  caddy_config:
  website_dist:
  game_web:
  roast-roulette_media:
    external: true

networks:
  default:
    name: proxy
    external: true
```

- [ ] **Step 3: On ThinkCentre — migrate data and populate static site volumes**

```bash
ssh thinkcentre 'OLD=~/dotfiles/hosts/thinkcentre/caddy && \
  NEW=~/Projects/dotfiles/hosts/thinkcentre/caddy && \
  docker compose -f $OLD/docker-compose.yml down && \
  docker volume create caddy_data && \
  docker volume create caddy_config && \
  docker volume create website_dist && \
  docker volume create game_web && \
  docker run --rm -v $OLD/data:/source:ro -v caddy_data:/dest alpine cp -a /source/. /dest/ && \
  docker run --rm -v $OLD/config:/source:ro -v caddy_config:/dest alpine cp -a /source/. /dest/ && \
  docker run --rm -v /home/chris/website/dist:/source:ro -v website_dist:/dest alpine cp -a /source/. /dest/ && \
  docker run --rm -v /home/chris/game/web:/source:ro -v game_web:/dest alpine cp -a /source/. /dest/ && \
  [ -f $NEW/.env ] || cp $OLD/.env $NEW/.env && \
  cd $NEW && docker compose up -d'
```

Note: `website_dist` and `game_web` are populated from the current host paths. **TODO: create a deploy script for repopulating static site volumes after rebuilding these projects.**

- [ ] **Step 4: Verify sites are working**

```bash
ssh thinkcentre "curl -s -o /dev/null -w '%{http_code}' https://christiantanul.com"
```

Expected: `200`

#### 7e: vaultwarden

- [ ] **Step 1: BACK UP FIRST (password vault data!)**

```bash
ssh thinkcentre 'cd ~/dotfiles/hosts/thinkcentre/vaultwarden && \
  tar czf ~/vaultwarden-backup-$(date +%Y%m%d).tar.gz vw-data'
```

- [ ] **Step 2: Update docker-compose.yml**

Change:
```yaml
    volumes:
      - ./vw-data:/data
```
To:
```yaml
    volumes:
      - vaultwarden_data:/data

volumes:
  vaultwarden_data:
```

- [ ] **Step 3: Wait for sync, then migrate data on ThinkCentre**

```bash
ssh thinkcentre 'OLD=~/dotfiles/hosts/thinkcentre/vaultwarden && \
  NEW=~/Projects/dotfiles/hosts/thinkcentre/vaultwarden && \
  docker compose -f $OLD/docker-compose.yml down && \
  docker volume create vaultwarden_data && \
  docker run --rm -v $OLD/vw-data:/source:ro -v vaultwarden_data:/dest alpine cp -a /source/. /dest/ && \
  cd $NEW && docker compose up -d'
```

- [ ] **Step 4: Verify Vaultwarden is accessible**

```bash
ssh thinkcentre "curl -s -o /dev/null -w '%{http_code}' https://vault.christiantanul.com"
```

#### 7f: plex

- [ ] **Step 1: Back up plex config**

```bash
ssh thinkcentre 'cd ~/dotfiles/hosts/thinkcentre/plex && \
  tar czf ~/plex-backup-$(date +%Y%m%d).tar.gz config'
```

- [ ] **Step 2: Update docker-compose.yml**

Change `./config:/config` to a named volume. Keep `/mnt/nas/media:/data/media:ro` (NAS mount) and `tmpfs: /transcode` as-is.

```yaml
    volumes:
      - plex_config:/config
      - /mnt/nas/media:/data/media:ro
```

Add:
```yaml
volumes:
  plex_config:
```

- [ ] **Step 3: Wait for sync, then migrate data on ThinkCentre**

```bash
ssh thinkcentre 'OLD=~/dotfiles/hosts/thinkcentre/plex && \
  NEW=~/Projects/dotfiles/hosts/thinkcentre/plex && \
  docker compose -f $OLD/docker-compose.yml down && \
  docker volume create plex_config && \
  docker run --rm -v $OLD/config:/source:ro -v plex_config:/dest alpine cp -a /source/. /dest/ && \
  cd $NEW && docker compose up -d'
```

Note: Plex config can be large. The copy step may take a while.

- [ ] **Step 4: Verify Plex is running**

```bash
ssh thinkcentre "docker ps --filter name=plex --format '{{.Status}}'"
```

#### 7g: home-assistant

- [ ] **Step 1: Back up HA config**

```bash
ssh thinkcentre 'cd ~/dotfiles/hosts/thinkcentre/home-assistant && \
  tar czf ~/ha-backup-$(date +%Y%m%d).tar.gz config'
```

- [ ] **Step 2: Update docker-compose.yml**

Change `./config:/config` to a named volume. Keep system bind mounts (`/etc/localtime`, `/var/run/dbus`) and NAS mounts as-is.

The config volume line changes from:
```yaml
      - ./config:/config
```
To:
```yaml
      - ha_config:/config
```

Add:
```yaml
volumes:
  ha_config:
```

- [ ] **Step 3: Wait for sync, then migrate data on ThinkCentre**

```bash
ssh thinkcentre 'OLD=~/dotfiles/hosts/thinkcentre/home-assistant && \
  NEW=~/Projects/dotfiles/hosts/thinkcentre/home-assistant && \
  docker compose -f $OLD/docker-compose.yml down && \
  docker volume create ha_config && \
  docker run --rm -v $OLD/config:/source:ro -v ha_config:/dest alpine cp -a /source/. /dest/ && \
  [ -f $NEW/.env ] || cp $OLD/.env $NEW/.env 2>/dev/null; \
  cd $NEW && docker compose up -d'
```

- [ ] **Step 4: Verify HA is accessible**

```bash
ssh thinkcentre "curl -s -o /dev/null -w '%{http_code}' http://localhost:8123"
```

Expected: `200` (or `401` if auth is required — both mean it's running).

- [ ] **Step 5: Commit all docker-compose changes**

```bash
cd ~/Projects/dotfiles && git add hosts/thinkcentre/*/docker-compose.yml && git commit -m "migrate service data from bind mounts to named volumes"
```

---

### Task 8: Update README.md

**Files:**
- Modify: `hosts/thinkcentre/README.md`

- [ ] **Step 1: Rewrite README.md**

```markdown
# ThinkCentre (NixOS)

## How It Works

Everything lives in `~/Projects/`, synced from Mac via Syncthing. No separate git
clone, no symlinks, no webhook.

**Infra services** (caddy, adguard, etc.) are in `dotfiles/hosts/thinkcentre/<service>/`.
**Your projects** (roast-roulette, hyperspace, etc.) are in `~/Projects/<project>/`.

Shell CDPATH is configured so `cd caddy` or `cd roast-roulette` works from anywhere.

## Quick Start

```bash
# See running containers
docker ps

# Navigate to a service
cd caddy

# Deploy/restart a service
cd caddy && docker compose up -d

# Rebuild NixOS
just rebuild
```

## Adding a New Service

1. Create a directory in `dotfiles/hosts/thinkcentre/<name>/` with a `docker-compose.yml`
2. `cd <name>` works immediately (CDPATH)
3. Create a `.env` file on ThinkCentre with production secrets
4. `docker compose up -d`

## Files

- `flake.nix` — NixOS system config (users, networking, firewall, Docker, Syncthing)
- `gaming-vm.nix` — Windows gaming VM with GPU passthrough
- `Justfile` — `just rebuild` to apply NixOS changes

## .env Files

- `.env` files contain production secrets and are gitignored + Syncthing-ignored
- `.env.example` files document required variables
- On ThinkCentre, `.env` contains `COMPOSE_FILE=docker-compose.production.yml`
- On Mac, `.env` contains `COMPOSE_FILE=docker-compose.local.yml`

## Docker Network

All reverse-proxied services use the `proxy` external network. Create it once:

```bash
docker network create proxy
```

## Native NixOS Services

Syncthing, Tailscale, Cockpit, OpenSSH run as native NixOS services (not Docker).
See `flake.nix` for configuration.
```

- [ ] **Step 2: Commit**

```bash
cd ~/Projects/dotfiles && git add hosts/thinkcentre/README.md && git commit -m "rewrite README for architecture v2"
```

---

### Task 9: Update SYNCTHING.md

**Files:**
- Modify: `hosts/thinkcentre/SYNCTHING.md`

- [ ] **Step 1: Rewrite SYNCTHING.md**

```markdown
# Syncthing Setup (Mac <-> ThinkCentre)

## How It Works

Syncthing bidirectionally syncs `~/Projects` between Mac and ThinkCentre.
This is the deployment mechanism — edit on Mac, changes appear on ThinkCentre automatically.

```
Mac: ~/Projects/dotfiles/hosts/thinkcentre/caddy/Caddyfile
                    | Syncthing (~15s on LAN)
ThinkCentre: ~/Projects/dotfiles/hosts/thinkcentre/caddy/Caddyfile
```

No git clone on ThinkCentre. No webhook. No symlinks.
NixOS changes require `just rebuild` after sync.

## Key Details

- **Folder ID**: `zd26e-jmupe` (label: "Projects")
- **Mac path**: `/Users/chris/Projects`
- **ThinkCentre path**: `/home/chris/Projects`
- **Syncthing runs as**: NixOS service, user `chris`, group `users`
- **GUI**: `https://syncthing.christiantanul.com` (ThinkCentre) or `http://localhost:8384` (Mac)
- **ThinkCentre config is declarative**: defined in `flake.nix` under `services.syncthing.settings`

## .stignore

Lives at `~/Projects/.stignore` (sync folder root). Key patterns:
- `.env` — production secrets never sync
- `**/.git` — git metadata stays per-machine
- `**/node_modules`, `**/target`, `**/dist`, etc. — build artifacts
- `**/*.sync-conflict-*` — Syncthing conflict files

## Gotchas

1. **File ownership**: Syncthing runs with group `users`. If files are owned by another group,
   sync silently fails. Fix: `sudo chown -R chris:users ~/Projects/`

2. **NixOS flake needs git**: Since `**/.git` is ignored, the Justfile `rebuild` recipe creates
   a throwaway git repo for Nix evaluation. This repo stays local (never syncs due to .stignore).

3. **Never rsync into ~/Projects/**: Let Syncthing be the sole sync mechanism.

4. **Conflict files**: If you edit the same file on both machines before sync completes,
   Syncthing creates `.sync-conflict-*` files. Check and resolve manually.
```

- [ ] **Step 2: Commit**

```bash
cd ~/Projects/dotfiles && git add hosts/thinkcentre/SYNCTHING.md && git commit -m "rewrite SYNCTHING.md for architecture v2"
```

---

### Task 10: Update OpenClaw docs

**Files:**
- Modify: `hosts/thinkcentre/openclaw/workspace/AGENTS.md`
- Modify: `hosts/thinkcentre/openclaw/config/skills/host-ssh/SKILL.md`

- [ ] **Step 1: Update AGENTS.md**

Replace the "Host Access (SSH)" section:

```markdown
## Host Access (SSH)
You can SSH into the ThinkCentre host machine:
```bash
ssh -i /home/node/.ssh/id_ed25519 -o StrictHostKeyChecking=no chris@host.docker.internal
```
This gives you full access to the host (NixOS, Docker, filesystem, etc.).

### Navigation
The shell has CDPATH configured, so you can `cd <service>` from anywhere:
- `cd caddy` — infra services in `~/Projects/dotfiles/hosts/thinkcentre/`
- `cd roast-roulette` — user projects in `~/Projects/`
- `just rebuild` — apply NixOS changes (run from ~)
```

- [ ] **Step 2: Update host-ssh/SKILL.md**

Replace the "Host Details" section:

```markdown
## Host Details
- Hostname: thinkcentre
- OS: NixOS
- User: chris (sudo NOPASSWD)
- Shell: zsh with CDPATH (cd <service> works from anywhere)
- Infra services: ~/Projects/dotfiles/hosts/thinkcentre/<service>/
- User projects: ~/Projects/<project>/
- NAS mounts: /mnt/nas/media, /mnt/nas/media_server, /mnt/nas/homes
- NixOS rebuild: `just rebuild` (from ~)
- Docker: `cd <service> && docker compose up -d`
```

Remove the line:
```
- Docker: all services run as docker-compose in ~/service-name/
```

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/dotfiles && git add hosts/thinkcentre/openclaw/ && git commit -m "update OpenClaw docs for architecture v2 paths"
```

---

### Task 11: Clean up old infrastructure on ThinkCentre

**Files:** None (ThinkCentre SSH commands)

**Do this LAST, after everything is verified working from the new paths.**

- [ ] **Step 1: Verify all services are running from new paths**

```bash
ssh thinkcentre "docker ps --format 'table {{.Names}}\t{{.Status}}' | sort"
```

All containers should show "Up" status.

- [ ] **Step 2: Remove old symlinks**

```bash
ssh thinkcentre 'for link in ~/caddy ~/adguard ~/openclaw ~/home-assistant ~/plex ~/vaultwarden ~/umami ~/iSponsorBlockTV ~/hyperspace; do
  [ -L "$link" ] && rm "$link" && echo "removed $link"
done'
```

- [ ] **Step 3: Remove old git clone**

Before deleting, check nothing unique exists there (like .env files not yet copied):

```bash
ssh thinkcentre "find ~/dotfiles -name '.env' -type f"
```

If all .env files were copied in Task 6, safe to remove:

```bash
ssh thinkcentre "rm -rf ~/dotfiles"
```

- [ ] **Step 4: Remove webhook (if still running)**

Check if a webhook service exists:

```bash
ssh thinkcentre "systemctl list-units --type=service | grep -i webhook"
```

If found, disable it. This may be a systemd unit defined in flake.nix — if so, remove it from flake.nix and rebuild. If it was set up manually, just disable it:

```bash
ssh thinkcentre "sudo systemctl stop dotfiles-webhook && sudo systemctl disable dotfiles-webhook"
```

- [ ] **Step 5: Remove old Justfile symlink if it conflicts**

```bash
ssh thinkcentre "ls -la ~/Justfile"
```

Should point to `Projects/dotfiles/hosts/thinkcentre/Justfile` (from home-manager). If it points to the old `~/dotfiles/...` path, run `just rebuild` to fix it.

- [ ] **Step 6: Final verification**

```bash
ssh thinkcentre 'echo "=== Home dir ===" && ls -la ~ && echo "=== CDPATH ===" && zsh -l -c "echo \$CDPATH" && echo "=== Services ===" && docker ps --format "table {{.Names}}\t{{.Status}}" | sort'
```

Expected:
- Home dir shows `Justfile -> Projects/...`, `README.md -> Projects/...`, `Projects/`
- CDPATH shows `.:$HOME/Projects/dotfiles/hosts/thinkcentre:$HOME/Projects`
- All containers Up
