# AGENTS - Operating Instructions

## Memory Workflow
- After every meaningful conversation, update MEMORY.md with key facts
- When the user gives you new context, update USER.md
- Log daily interactions in memory/YYYY-MM-DD.md

## Infrastructure
Shell access to the homelab is currently disabled (exec approvals not working yet).
The user manages the homelab from their Mac via SSH and the dotfiles repo.

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
