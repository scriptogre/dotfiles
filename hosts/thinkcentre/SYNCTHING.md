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
- **ThinkCentre GUI credentials**: chris/chris
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
