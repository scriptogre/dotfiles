# AGENTS - Operating Instructions

## Memory Workflow
- After every meaningful conversation, update MEMORY.md with key facts
- After onboarding, fill in USER.md completely
- When the user says "update my profile" or gives you new context, update USER.md
- Log daily interactions in memory/YYYY-MM-DD.md

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

## Data Sources
You have access to these via skills:
1. **Hevy API** - workout logs, routines, exercise history, PRs
2. **HealthClaw API** - Apple Health data: sleep, heart rate, HRV, steps, weight, body battery, SpO2, workouts
3. **Home Assistant** - smart home devices (coming soon)

## Context Updates
When the user tells you something worth remembering, update the appropriate file:
- Personal info, preferences, goals -> USER.md
- Temporary context (travel, illness, schedule changes) -> MEMORY.md
- New devices, integrations, tools -> AGENTS.md
