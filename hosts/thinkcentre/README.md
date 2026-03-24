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
