# Syncthing Setup (Mac ↔ ThinkCentre)

## How It Works

Syncthing bidirectionally syncs `~/Projects` between the Mac and ThinkCentre.
This means `~/Projects/dotfiles` (this repo) is always in sync on both machines.

```
Mac: ~/Projects/dotfiles/hosts/thinkcentre/caddy/Caddyfile
                    ↕ Syncthing (automatic, ~15s on LAN)
ThinkCentre: ~/Projects/dotfiles/hosts/thinkcentre/caddy/Caddyfile
                    ↑ home-manager symlink (mkOutOfStoreSymlink)
ThinkCentre: ~/caddy/Caddyfile
```

Edit on either machine → Syncthing propagates → done.
`just thinkcentre` (from Mac) or `just` (on ThinkCentre) only needed for NixOS system changes (flake.nix).

## Key Details

- **Folder ID**: `zd26e-jmupe` (label: "Projects")
- **Mac path**: `/Users/chris/Projects`
- **ThinkCentre path**: `/home/chris/Projects`
- **Syncthing runs as**: NixOS service, user `chris`, group `users` (not `syncthing` — must match file ownership)
- **GUI**: `https://syncthing.christiantanul.com` (ThinkCentre) or `http://localhost:8384` (Mac)
- **ThinkCentre GUI credentials**: chris/chris
- **ThinkCentre config is declarative**: devices, folders, and watcher settings are defined in
  `flake.nix` under `services.syncthing.settings`. Don't configure these via the Syncthing UI/API —
  they'll be overwritten on rebuild. The Mac's Syncthing config is NOT declarative (managed via its UI).

## Ignore Patterns

`.stignore` at `~/Projects/.stignore` excludes build artifacts, caches, and secrets from syncing.
The file lives in the Projects root (not in dotfiles) because Syncthing reads it from the folder root.

Ignored: `.git`, `node_modules`, `dist`, `.next`, `__pycache__`, `target`, `.cache`, `.ruff_cache`,
`.pytest_cache`, `.mypy_cache`, `.turbo`, `.sandbox`, `.venv`, `venv`, `.idea`, `.env`, `*.env`,
`.stfolder`, `.stversions`, `*.sync-conflict-*`, `*.hm-backup`

## Gotchas

1. **File ownership**: Syncthing must run with group `users` (set in flake.nix: `services.syncthing.group = "users"`).
   If files are owned by a different group, Syncthing can't overwrite them and sync silently fails.
   Symptom: `.syncthing.*.tmp` files that never get renamed.
   Fix: `sudo chown -R chris:users ~/Projects/`

2. **Firewall**: Port 8384 must be open for Caddy to reach the Syncthing GUI.
   The Syncthing data port (22000) is handled by Tailscale's trusted interface.

3. **Symlinks**: `~/caddy`, `~/adguard`, etc. on ThinkCentre are symlinks to
   `~/Projects/dotfiles/hosts/thinkcentre/<service>/` via home-manager's `mkOutOfStoreSymlink`.
   These are created by `nixos-rebuild` — adding a new service directory requires a rebuild
   to create the symlink, but no flake.nix editing (auto-discovered).

4. **rsync conflict**: Never rsync files into `~/Projects/` on the ThinkCentre — it creates
   ownership/index conflicts with Syncthing. Always let Syncthing be the sole sync mechanism.

5. **`.stignore` not applying**: If global file count is unexpectedly high, check that the
   `.stignore` file exists at the folder root on both machines. Push it via the Syncthing API
   or `scp` if needed.
