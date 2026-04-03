# AGENTS - Operating Instructions

## Memory Workflow
- After every meaningful conversation, update MEMORY.md with key facts
- When the user gives you new context, update USER.md
- Log daily interactions in memory/YYYY-MM-DD.md

## Infrastructure Access (SSH)

You can SSH into two machines from inside the container.

### ThinkCentre (NixOS server)
```bash
ssh -i /home/node/.ssh/id_ed25519 -o StrictHostKeyChecking=no chris@host.docker.internal "command here"
```
- Full access as chris (sudo NOPASSWD)
- Shell has CDPATH: `cd <service>` works from anywhere
- **To understand the setup, read the config files:**
  - `~/Projects/dotfiles/hosts/thinkcentre/flake.nix` - NixOS system config
  - `ls ~/Projects/dotfiles/hosts/thinkcentre/` - each subdir is a Docker service
  - `~/Projects/dotfiles/hosts/thinkcentre/caddy/Caddyfile` - domains and proxying
- Caddy reload: `cd caddy && just` (NOT docker exec)
- NixOS rebuild: `just rebuild` (from ~) - ONLY when user explicitly asks

### Synology DS923+ (NAS)
```bash
ssh -i /home/node/.ssh/id_ed25519 -o StrictHostKeyChecking=no chris@192.168.0.14 "command here"
```
- Access as chris
- Not declaratively managed - explore with `ls`, `df`, `docker ps`, `synopkg list`

## Data Sources
You have access to these via skills:
1. **Hevy API** - workout logs, routines, exercise history, PRs
2. **HealthClaw API** - Apple Health data: sleep, heart rate, HRV, steps, weight, body battery, SpO2, workouts
3. **Weather** - Open-Meteo API (no key needed)

## Context Updates
When the user tells you something worth remembering, update the appropriate file:
- Personal info, preferences, goals -> USER.md
- Temporary context (travel, illness, schedule changes) -> MEMORY.md
- New devices, integrations, tools -> AGENTS.md
