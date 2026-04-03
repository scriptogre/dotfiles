---
name: homelab
description: "Manage and monitor the homelab infrastructure. Use when the user asks about server status, Docker containers, disk space, services, NAS, backups, networking, or anything infrastructure-related."
---

# Homelab Skill

Two machines accessible via SSH. The setup changes frequently - always read the actual config files instead of assuming what's running.

SSH prefix for both machines:
```
ssh -i /home/node/.ssh/id_ed25519 -o StrictHostKeyChecking=no
```

## ThinkCentre (NixOS - chris@host.docker.internal)

Everything is declarative. Read config files to understand the current state.

### Discover what's running
```bash
# Docker services
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# System overview
uptime && free -h && df -h / /home

# Failed systemd services
systemctl --failed

# NAS mount status
mount | grep nas
```

### Understand the setup
```bash
# What Docker services exist (each subdir has a docker-compose.yml)
ls ~/Projects/dotfiles/hosts/thinkcentre/

# NixOS system config (packages, networking, mounts, firewall)
cat ~/Projects/dotfiles/hosts/thinkcentre/flake.nix

# Reverse proxy config (all domains, upstreams)
cat ~/Projects/dotfiles/hosts/thinkcentre/caddy/Caddyfile

# Specific service config
cat ~/Projects/dotfiles/hosts/thinkcentre/<service>/docker-compose.yml
```

### Service management
```bash
# Restart a service
cd ~/Projects/dotfiles/hosts/thinkcentre/<service> && docker compose restart

# Rebuild and restart
cd ~/Projects/dotfiles/hosts/thinkcentre/<service> && docker compose up -d --build

# Service logs
docker logs --tail 50 <container_name>

# Caddy reload (zero-downtime) - NEVER use docker exec
cd ~/Projects/dotfiles/hosts/thinkcentre/caddy && just

# NixOS rebuild - ONLY when user explicitly asks
just rebuild
```

## Synology DS923+ (NAS - chris@192.168.0.14)

Not declaratively managed. Explore to understand current state.

```bash
# System info
uptime

# Disk/volume status
df -h /volume1 /volume2

# Installed packages
synopkg list --name

# Docker containers
docker ps -a --format "table {{.Names}}\t{{.Status}}"
```

## Rules
- Read config files to answer questions about the setup - don't guess
- For checks (status, disk, logs): just run commands
- For changes (restart, rebuild, delete): explain what and why first
- Never run `just rebuild` without explicit user request
- Never modify config files on disk - those are managed from the dotfiles repo on the Mac
- Caddy reload is `cd caddy && just`, never `docker exec caddy caddy reload`
