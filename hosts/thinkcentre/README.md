# ThinkCentre (NixOS)

## How It Works

The dotfiles repo is cloned to `~/dotfiles` on the ThinkCentre. Service directories
(any directory here containing a `docker-compose.yml`) are symlinked into `~/` so that
`~/caddy`, `~/adguard`, etc. point to `~/dotfiles/hosts/thinkcentre/caddy/`, etc.

**The workflow:**
1. Edit files on Mac (`~/Projects/dotfiles`) or ThinkCentre (`~/dotfiles`)
2. Commit and push to Gitea
3. Gitea webhook automatically runs `git pull` + `just link` on the ThinkCentre
4. Services pick up changes (Caddy auto-reloads via the caddy-reload sidecar)

For NixOS system changes (flake.nix), run `just` on the ThinkCentre or `just thinkcentre` from the Mac.

## Files

- `flake.nix` — NixOS system config (users, networking, firewall, Docker, services)
- `gaming-vm.nix` — Windows gaming VM with GPU passthrough (VFIO, libvirt, Cockpit)
- `Justfile` — Task runner (symlinked to `~/Justfile`)

## Adding a New Service

1. Create a directory here with a `docker-compose.yml`
2. Commit and push
3. The webhook runs `just link` which creates the `~/service` symlink automatically
4. SSH in and `cd ~/service && docker compose up -d`

## Symlinks

`just link` auto-discovers directories with `docker-compose.yml` and creates:
```
~/caddy        → ~/dotfiles/hosts/thinkcentre/caddy/
~/adguard      → ~/dotfiles/hosts/thinkcentre/adguard/
~/Justfile     → ~/dotfiles/hosts/thinkcentre/Justfile
```

These are simple `ln -s` symlinks. No Nix store, no bind mounts.

## Webhook

A systemd service (`dotfiles-webhook`) listens on port 9876. Configure in Gitea:
Repository → Settings → Webhooks → Add Webhook → POST `http://thinkcentre:9876`

## Native NixOS Services

Some services run natively instead of Docker: syncthing, tailscale, cockpit, openssh.
See `flake.nix` for their configuration.
