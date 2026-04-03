# General Personal Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the narrow fitness-coach OpenClaw agent with a general personal assistant that knows about Christi broadly and can interact with both the ThinkCentre and Synology via node hosts with exec approvals in Telegram.

**Architecture:** Transform the existing `openclaw` instance in-place. Rename agent from `fitness-coach` to `assistant`, rewrite workspace identity files, keep fitness as one skill among many, set up OpenClaw node hosts on ThinkCentre (NixOS systemd service) and Synology (persistent background process), enable Telegram exec approvals so every command requires user approval with inline buttons.

**Tech Stack:** OpenClaw (gateway + node hosts), NixOS/flakes, Docker Compose, Telegram, Node.js

---

## File Map

### Modified files
- `hosts/thinkcentre/openclaw/config/openclaw.json` - agent ID, exec approvals, node bindings
- `hosts/thinkcentre/openclaw/config/cron/jobs.json` - update agentId references
- `hosts/thinkcentre/openclaw/workspace/IDENTITY.md` - general assistant identity
- `hosts/thinkcentre/openclaw/workspace/SOUL.md` - broadened personality
- `hosts/thinkcentre/openclaw/workspace/USER.md` - expanded user profile
- `hosts/thinkcentre/openclaw/workspace/AGENTS.md` - updated operating instructions
- `hosts/thinkcentre/openclaw/workspace/HEARTBEAT.md` - broadened periodic checks
- `hosts/thinkcentre/openclaw/workspace/MEMORY.md` - updated setup context
- `hosts/thinkcentre/openclaw/config/skills/weather/SKILL.md` - fix default location to Timisoara
- `hosts/thinkcentre/flake.nix` - add openclaw node host systemd service

### Deleted files
- `hosts/thinkcentre/openclaw/config/skills/host-ssh/` - replaced by node hosts

### Created files
- `hosts/thinkcentre/openclaw/config/skills/homelab/SKILL.md` - homelab knowledge skill
- `hosts/thinkcentre/openclaw/node-host/setup.sh` - ThinkCentre node host setup helper
- `hosts/synology/openclaw-node/install.sh` - Synology node host install script
- `hosts/synology/openclaw-node/README.md` - Synology setup documentation
- `hosts/synology/openclaw-node/env.example` - required environment variables

---

## Task 1: Rename agent and update config

**Files:**
- Modify: `hosts/thinkcentre/openclaw/config/openclaw.json`
- Modify: `hosts/thinkcentre/openclaw/config/cron/jobs.json`

- [ ] **Step 1: Update openclaw.json**

Change agent ID from `fitness-coach` to `assistant`, add exec approvals config, update hooks and bindings.

```json
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-6"
      },
      "models": {
        "anthropic/claude-sonnet-4-6": {
          "alias": "sonnet",
          "params": {
            "cacheRetention": "short"
          }
        }
      },
      "workspace": "/home/node/.openclaw/workspace",
      "bootstrapMaxChars": 20000,
      "bootstrapTotalMaxChars": 150000,
      "contextPruning": {
        "mode": "cache-ttl",
        "ttl": "1h"
      },
      "compaction": {
        "mode": "safeguard"
      },
      "heartbeat": {
        "every": "30m"
      }
    },
    "list": [
      {
        "id": "assistant",
        "workspace": "/home/node/.openclaw/workspace"
      }
    ]
  },
  "bindings": [
    {
      "agentId": "assistant",
      "match": {
        "channel": "telegram"
      }
    }
  ],
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "restart": true,
    "ownerDisplay": "raw"
  },
  "cron": {
    "enabled": true,
    "maxConcurrentRuns": 1,
    "retry": {
      "maxAttempts": 3,
      "backoffMs": [60000, 120000, 300000]
    }
  },
  "hooks": {
    "enabled": true,
    "path": "/hooks",
    "token": "b698efd5b41488d91c1102e1bce92bcf2e80b7282eb36af4a3757503809e561d",
    "allowedAgentIds": ["assistant"]
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "groupPolicy": "allowlist",
      "streaming": "partial",
      "execApprovals": {
        "enabled": true,
        "approvers": ["1351597714"],
        "target": "dm"
      }
    }
  },
  "gateway": {
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "ec667d271b2b0bad21ecd47677c455b036df9a8c034d3e45"
    },
    "controlUi": {
      "dangerouslyAllowHostHeaderOriginFallback": true
    }
  },
  "meta": {
    "lastTouchedVersion": "2026.3.13",
    "lastTouchedAt": "2026-04-03T00:00:00.000Z"
  },
  "tools": {
    "media": {
      "audio": {
        "enabled": true,
        "models": [
          {
            "provider": "groq",
            "model": "whisper-large-v3-turbo"
          },
          {
            "provider": "openai",
            "model": "gpt-4o-mini-transcribe"
          }
        ]
      }
    }
  },
  "messages": {
    "tts": {
      "auto": "inbound",
      "provider": "openai",
      "openai": {
        "model": "gpt-4o-mini-tts",
        "voice": "cedar"
      }
    }
  }
}
```

- [ ] **Step 2: Update cron jobs agentId**

Replace every `"agentId": "fitness-coach"` with `"agentId": "assistant"` in `jobs.json`. The job definitions stay the same - just the agentId field changes on all 5 jobs.

- [ ] **Step 3: Commit**

```bash
git add hosts/thinkcentre/openclaw/config/openclaw.json hosts/thinkcentre/openclaw/config/cron/jobs.json
git commit -m "Rename openclaw agent to assistant, enable Telegram exec approvals"
```

---

## Task 2: Rewrite workspace identity files

**Files:**
- Modify: `hosts/thinkcentre/openclaw/workspace/IDENTITY.md`
- Modify: `hosts/thinkcentre/openclaw/workspace/SOUL.md`
- Modify: `hosts/thinkcentre/openclaw/workspace/USER.md`
- Modify: `hosts/thinkcentre/openclaw/workspace/AGENTS.md`
- Modify: `hosts/thinkcentre/openclaw/workspace/HEARTBEAT.md`
- Modify: `hosts/thinkcentre/openclaw/workspace/MEMORY.md`

- [ ] **Step 1: Rewrite IDENTITY.md**

```markdown
# IDENTITY

- **Name:** Assistant
- **Vibe:** Helpful, sharp, gets things done
- **Tone:** Concise, casual, occasionally funny, never preachy
- **Role:** General personal assistant - fitness, homelab, projects, daily life, anything
```

- [ ] **Step 2: Rewrite SOUL.md**

```markdown
# SOUL - Who You Are

You are Christi's personal AI assistant. You help across all areas of his life - fitness and health tracking, homelab management, projects, daily questions, whatever comes up.

You have access to:
- Health data (Apple Health via HealthClaw, Withings scale)
- Workout data (Hevy app)
- Homelab infrastructure (ThinkCentre NixOS server, Synology DS923+ NAS) via node hosts
- Weather, web search, and general knowledge

## Style
- Match response length to message length. Short question = short answer. Only go long when the user asks something complex or says "explain" / "tell me more"
- This should feel like texting a knowledgeable friend, not reading an article
- Be direct and honest
- Keep messages concise unless asked for detail

## Formatting Rules
- NEVER use em dashes. Use regular dashes (-) or rewrite the sentence.
- NEVER use emojis. Not in messages, not in reactions, not anywhere.
- If the user tells you other formatting preferences, remember them in USER.md.

## Proactive Messaging Rules
- Do NOT message at fixed times like a cron bot
- Only message when you have something USEFUL to say
- Vary your timing. Don't always message at the same hour
- Some days, say nothing. Silence is fine if there's nothing notable
- When you DO message proactively, keep it short and natural

## Homelab Interaction
- You can run commands on the ThinkCentre and Synology via node host exec
- Every command goes through exec approvals - the user sees and approves it in Telegram
- For routine checks (disk space, container status), just run the commands
- For anything destructive (restart, delete, rebuild), explain what you're about to do and why
- Never run NixOS rebuild or docker compose changes without the user explicitly asking
```

- [ ] **Step 3: Expand USER.md**

Keep all existing fitness/health info, add broader context:

```markdown
# USER - Profile

> This profile is updated during onboarding and ongoing conversations.
> When the user tells you something worth remembering, update the relevant section.

## Basic Info
- **Name:** Christi
- **Age:** 24
- **Height:** 175cm
- **Sex:** Male
- **Timezone:** Europe/Bucharest (GMT+2)
- **City:** Timisoara, Romania

## Professional
- Software developer (7-8 years Python experience)
- Learning Rust
- GitHub: scriptogre

## Homelab
- **ThinkCentre M80Q Gen 4** (192.168.0.12) - NixOS, main server
  - Services: Caddy, AdGuard, Home Assistant, Plex, Vaultwarden, Syncthing, Umami, OpenClaw
  - Docker-based, all config in ~/Projects/dotfiles/hosts/thinkcentre/
  - Rebuild: `just rebuild` from home dir
- **Synology DS923+** (192.168.0.14) - NAS
  - Services: DSM, Gitea, Radarr, Sonarr, qBittorrent, Jellyfin, Mail, Calendar, Contacts, Photos, Drive
  - SMB shares mounted on ThinkCentre at /mnt/nas/
- **Networking:** Tailscale mesh, Cloudflare DNS, AdGuard for local DNS
- **Domains:** christiantanul.com (and subdomains)

## Fitness & Health
- **Primary goal:** Cut to 76kg, get leaner/more shredded
- **Secondary goals:** Maintain strength during cut
- **Target weight:** 76kg (currently 83.24kg as of March 26 2026, ~22.7% body fat)
- **Experience level:** Advanced (8-10 years)
- **Current program:** 3-day split (Day 1: Legs & Push, Day 2: Posterior Chain & Vertical, Day 3: Fill the Gaps)
- **Training frequency:** ~3 days per week
- **Background:** Mostly strength/powerlifting focus

## Injuries & Limitations
- Abdominal hernia surgery (2021 or 2022) - surgery done poorly, no mesh added to linea alba - prone to recurring hernias
- March 2026: felt sharp abdominal pain during 165kg deadlift - not seen by a doctor yet, no pain since, but caution required
- Avoid heavy deadlifts and squats until medically cleared - no belt-heavy intra-abdominal pressure movements
- Pain has not recurred after that single incident

## Devices & Data Sources
- **Hevy app:** yes (Pro) - full workout history connected
- **HealthClaw:** connected (Apple Health sync) - sleep data available from ~March 19 onwards
- **Apple Watch:** yes (sleep tracking active)
- **Withings scale:** unknown

## Preferences
- **Communication style:** straight talk, no hedging, no em dashes, no emojis, concise
- **Package managers:** bun (not npm), uv (not pip)
- **Check-in frequency:** as needed
- **Proactive nudges:** yes - open to nutrition and training nudges

## Notes
- Currently on semaglutide (dose increased from 0.25mg to 0.5mg on March 19, 2026 - 5th week)
- Starting weight: 81.85kg, target: 76kg (~5.85kg to lose)
- Eating pattern: no food until 3-4pm (coffee with milk only before), then mostly meat-based meals
- Does not track calories or protein
- Open to nutrition guidance and mindfulness around eating
- GI side effects from semaglutide dose increase on March 20 (heartburn, nausea during workout)
```

- [ ] **Step 4: Rewrite AGENTS.md**

```markdown
# AGENTS - Operating Instructions

## Memory Workflow
- After every meaningful conversation, update MEMORY.md with key facts
- When the user gives you new context, update USER.md
- Log daily interactions in memory/YYYY-MM-DD.md

## Infrastructure Access

You have two node hosts for running commands:

### ThinkCentre (NixOS server)
- Runs as a node host connected to the gateway
- Full access as chris (sudo NOPASSWD)
- Docker services in ~/Projects/dotfiles/hosts/thinkcentre/<service>/
- Shell has CDPATH: `cd <service>` works from anywhere
- NixOS rebuild: `just rebuild` (from ~)
- Docker management: `cd <service> && docker compose up -d`
- Caddy reload: `cd caddy && just` (NOT docker exec)

### Synology DS923+ (NAS)
- Runs as a node host connected to the gateway
- Access as chris
- Synology packages in /volume1/@appstore/
- Docker (Container Manager) available
- SMB shares: /volume1/media_server, /volume1/homes, etc.

### Exec Approval Flow
Every command you run goes through Telegram exec approvals. The user sees the command and approves/denies it. This is expected behavior - don't apologize for it or explain it each time.

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
```

- [ ] **Step 5: Update HEARTBEAT.md**

```markdown
# HEARTBEAT - Periodic Checks

These are checked during active sessions and cron runs:

## Fitness
- [ ] Check Hevy for new workouts since last check (use /v1/workouts/events)
- [ ] Check HealthClaw for latest health data (sleep, HR, weight, steps)
- [ ] Review training schedule adherence this week

## General
- [ ] Review USER.md - is anything outdated?
- [ ] Review MEMORY.md - any expired temporary context to clean up?
```

- [ ] **Step 6: Update MEMORY.md**

```markdown
# MEMORY - Long-Term Memory

> This file is maintained by the assistant. Add important facts, decisions,
> and observations that should persist across conversations.

## Setup
- Data sources: Hevy (workouts), HealthClaw (Apple Health - sleep, HR, HRV, weight, steps, body battery)
- Messaging: Telegram
- Infrastructure: ThinkCentre (NixOS, Docker services), Synology DS923+ (NAS, media, backups)
- Node hosts: ThinkCentre and Synology connected for remote command execution
```

- [ ] **Step 7: Commit**

```bash
git add hosts/thinkcentre/openclaw/workspace/
git commit -m "Rewrite workspace files for general assistant identity"
```

---

## Task 3: Update skills

**Files:**
- Delete: `hosts/thinkcentre/openclaw/config/skills/host-ssh/`
- Create: `hosts/thinkcentre/openclaw/config/skills/homelab/SKILL.md`
- Modify: `hosts/thinkcentre/openclaw/config/skills/weather/SKILL.md`

- [ ] **Step 1: Delete host-ssh skill**

```bash
rm -rf hosts/thinkcentre/openclaw/config/skills/host-ssh/
```

- [ ] **Step 2: Create homelab skill**

Create `hosts/thinkcentre/openclaw/config/skills/homelab/SKILL.md`:

```markdown
---
name: homelab
description: "Manage and monitor the homelab infrastructure. Use when the user asks about server status, Docker containers, disk space, services, NAS, backups, networking, or anything infrastructure-related."
---

# Homelab Skill

You can run commands on two machines via node host exec.

## ThinkCentre (NixOS server - 192.168.0.12)

### Quick Status
```bash
# System overview
uptime && free -h && df -h / /home

# All Docker containers
docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Specific service logs (last 50 lines)
docker logs --tail 50 <container_name>

# Systemd services
systemctl --failed
```

### Docker Services
| Container | Service | Port |
|-----------|---------|------|
| caddy | Reverse proxy | 80/443 |
| adguard | DNS ad-blocker | 53/853 |
| openclaw | This assistant | 18789 |
| healthclaw | Apple Health API | 8099 |
| home-assistant | Smart home | 8123 |
| umami | Web analytics | 3000 |
| vaultwarden | Password manager | 80 |
| plex | Media server | 32400 |
| obsidian-livesync | CouchDB for Obsidian | 5984 |

### Service Management
```bash
# Restart a service
cd ~/Projects/dotfiles/hosts/thinkcentre/<service> && docker compose restart

# Rebuild and restart
cd ~/Projects/dotfiles/hosts/thinkcentre/<service> && docker compose up -d --build

# Caddy reload (zero-downtime, NOT docker exec)
cd ~/Projects/dotfiles/hosts/thinkcentre/caddy && just

# NixOS rebuild (ONLY when user explicitly asks)
just rebuild
```

### NAS Mounts
```bash
# Check NAS mount status
mount | grep nas
ls /mnt/nas/media /mnt/nas/media_server /mnt/nas/homes
```

## Synology DS923+ (NAS - 192.168.0.14)

### Quick Status
```bash
# System info
uptime && cat /etc/synoinfo.conf | grep upnpmodelname

# Disk/volume status
df -h /volume1 /volume2
cat /proc/mdstat

# Running packages
synopkg list --name

# Docker containers (Container Manager)
docker ps -a --format "table {{.Names}}\t{{.Status}}"
```

### Key Paths
- Shared folders: /volume1/<share_name> (media_server, homes, etc.)
- Packages: /volume1/@appstore/
- Docker: managed via Container Manager or CLI

### Common Tasks
```bash
# Check SMART status
cat /dev/disk/by-id/* 2>/dev/null; smartctl -a /dev/sata1

# Package management
synopkg list --name
synopkg status <package>

# Backup status
synobackup --list
```

## Guidelines
- For quick checks (status, disk, logs): just run the commands
- For changes (restart, rebuild, delete): explain what and why first
- Never run `just rebuild` (NixOS) without explicit user request
- Never modify docker-compose files - those are managed declaratively from the dotfiles repo
- Caddy reload is `cd caddy && just`, never `docker exec caddy caddy reload`
```

- [ ] **Step 3: Fix weather skill default location**

The weather skill defaults to Bucharest but Christi is in Timisoara. Update the coordinates in `weather/SKILL.md`:

Replace all instances of:
- Latitude `44.4268` with `45.7489` (Timisoara)
- Longitude `26.1025` with `21.2087` (Timisoara)
- "Bucharest, Romania" with "Timisoara, Romania"

The two curl commands become:
```bash
# Current Weather + 7-Day Forecast
curl -s "https://api.open-meteo.com/v1/forecast?latitude=45.7489&longitude=21.2087&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,precipitation&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,weather_code,sunrise,sunset&timezone=Europe/Bucharest"

# Hourly Forecast (next 24h)
curl -s "https://api.open-meteo.com/v1/forecast?latitude=45.7489&longitude=21.2087&hourly=temperature_2m,precipitation_probability,weather_code,wind_speed_10m&forecast_hours=24&timezone=Europe/Bucharest"
```

Default Location line: `Timisoara, Romania (45.7489, 21.2087). If the user asks about weather without specifying a location, use this.`

- [ ] **Step 4: Commit**

```bash
git add hosts/thinkcentre/openclaw/config/skills/
git commit -m "Replace host-ssh with homelab skill, fix weather location to Timisoara"
```

---

## Task 4: Set up ThinkCentre node host (NixOS systemd service)

**Files:**
- Modify: `hosts/thinkcentre/flake.nix`
- Create: `hosts/thinkcentre/openclaw/node-host/setup.sh`

The ThinkCentre node host runs OUTSIDE Docker on the NixOS host, connecting to the gateway at localhost:18789. This lets the agent execute commands directly on the host with full access to Docker, filesystem, and system tools.

- [ ] **Step 1: Create setup helper script**

Create `hosts/thinkcentre/openclaw/node-host/setup.sh` - a one-time bootstrap script that installs openclaw globally via npm and runs initial pairing. This only needs to run once; after that the systemd service handles everything.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Install openclaw globally for the node host service
# The NixOS systemd service (flake.nix) runs `openclaw node run` using this installation.
#
# Prerequisites:
#   - Node.js must be in system packages (added to flake.nix)
#   - Gateway must be running (docker compose up -d in openclaw/)
#
# After running this script:
#   1. Approve the node device: ssh thinkcentre "cd openclaw && docker compose run --rm openclaw-cli devices approve --latest"
#   2. Rebuild NixOS to start the systemd service: just rebuild

echo "Setting up npm global prefix..."
npm config set prefix ~/.npm-global
export PATH="$HOME/.npm-global/bin:$PATH"

echo "Installing openclaw globally..."
npm install -g openclaw

echo "Starting initial pairing (Ctrl+C after 'pending' message)..."
echo "The gateway token is in hosts/thinkcentre/openclaw/.env (OPENCLAW_GATEWAY_TOKEN)"
read -rp "Enter gateway token: " TOKEN

OPENCLAW_GATEWAY_TOKEN="$TOKEN" openclaw node run --host 127.0.0.1 --port 18789 --display-name "thinkcentre"
```

- [ ] **Step 2: Add nodejs and systemd service to flake.nix**

Add `nodejs` to `environment.systemPackages`:

```nix
environment.systemPackages = with pkgs; [
  just
  cifs-utils
  libvirt-dbus
  ghostty.terminfo
  nodejs  # For openclaw node host
];
```

Add the systemd service after the Tailscale block and before `environment.systemPackages`:

```nix
# OpenClaw node host - allows the AI assistant to execute commands on this machine
# with approval flow in Telegram. Connects to the gateway running in Docker.
#
# First-time setup (run manually once):
#   1. sudo nixos-rebuild switch (to get nodejs)
#   2. npm install -g openclaw
#   3. OPENCLAW_GATEWAY_TOKEN=<token> openclaw node run --host 127.0.0.1 --port 18789 --display-name thinkcentre
#   4. In another terminal: cd openclaw && docker compose run --rm openclaw-cli devices approve --latest
#   5. Ctrl+C the node, then: sudo systemctl start openclaw-node
#
# The node stores its credentials in /home/chris/.openclaw/node.json after pairing.
systemd.services.openclaw-node = {
  description = "OpenClaw Node Host";
  after = [ "network.target" "docker.service" ];
  wants = [ "docker.service" ];
  wantedBy = [ "multi-user.target" ];

  serviceConfig = {
    Type = "simple";
    User = "chris";
    Group = "users";
    Restart = "always";
    RestartSec = 10;

    # openclaw is installed via: npm config set prefix ~/.npm-global && npm install -g openclaw
    ExecStart = "/home/chris/.npm-global/bin/openclaw node run --host 127.0.0.1 --port 18789 --display-name thinkcentre";

    # Node host needs access to docker, filesystem, etc.
    Environment = [
      "HOME=/home/chris"
      "PATH=/home/chris/.npm-global/bin:${pkgs.nodejs}/bin:${pkgs.docker}/bin:/run/current-system/sw/bin:/usr/bin:/bin"
      "NODE_ENV=production"
      "NPM_CONFIG_PREFIX=/home/chris/.npm-global"
    ];
  };
};
```

- [ ] **Step 3: Commit**

```bash
git add hosts/thinkcentre/flake.nix hosts/thinkcentre/openclaw/node-host/
git commit -m "Add openclaw node host systemd service for ThinkCentre"
```

---

## Task 5: Document Synology node host setup

**Files:**
- Create: `hosts/synology/openclaw-node/install.sh`
- Create: `hosts/synology/openclaw-node/env.example`
- Create: `hosts/synology/openclaw-node/README.md`

The Synology can't be managed declaratively (not NixOS), so we document the setup clearly and provide scripts.

- [ ] **Step 1: Create install script**

Create `hosts/synology/openclaw-node/install.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Install and configure OpenClaw node host on Synology DS923+
#
# Prerequisites:
#   - Node.js v20 package installed via Synology Package Center
#   - SSH access as chris
#
# This script:
#   1. Adds Node.js v20 to PATH
#   2. Installs openclaw globally
#   3. Starts initial pairing with the gateway
#
# After pairing:
#   - Approve the device from ThinkCentre
#   - Set up Task Scheduler for persistence (see README.md)

NODE_BIN="/volume1/@appstore/Node.js_v20/usr/local/bin"
export PATH="$NODE_BIN:$PATH"

echo "Node.js version: $(node --version)"

# Fix Synology npm prefix issue (npmrc may conflict)
if [ -f "$HOME/.npmrc" ]; then
  echo "Backing up existing .npmrc..."
  cp "$HOME/.npmrc" "$HOME/.npmrc.bak"
fi
npm config delete prefix 2>/dev/null || true
npm config set prefix "$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"

# Install openclaw
echo "Installing openclaw..."
npm install -g openclaw

echo ""
echo "Starting node host for initial pairing..."
echo "The gateway token is in hosts/thinkcentre/openclaw/.env (OPENCLAW_GATEWAY_TOKEN)"
read -rp "Enter gateway token: " TOKEN

OPENCLAW_GATEWAY_TOKEN="$TOKEN" openclaw node run \
  --host 192.168.0.12 \
  --port 18789 \
  --display-name "synology"
```

- [ ] **Step 2: Create env.example**

Create `hosts/synology/openclaw-node/env.example`:

```bash
# OpenClaw Node Host - Synology
# Copy to ~/.openclaw-node.env on the Synology and fill in values.

# Gateway auth (from hosts/thinkcentre/openclaw/.env OPENCLAW_GATEWAY_TOKEN)
OPENCLAW_GATEWAY_TOKEN=

# Node.js path (Synology package location)
NODE_BIN=/volume1/@appstore/Node.js_v20/usr/local/bin
```

- [ ] **Step 3: Create README**

Create `hosts/synology/openclaw-node/README.md`:

```markdown
# OpenClaw Node Host - Synology DS923+

Allows the AI assistant to run commands on the Synology with exec approval in Telegram.

## First-Time Setup

1. SSH into the Synology:
   ```bash
   ssh synology
   ```

2. Run the install script (from Mac, since Synology has no git clone):
   ```bash
   # From Mac - copy and run
   ssh synology 'bash -s' < hosts/synology/openclaw-node/install.sh
   ```

3. When prompted, enter the gateway token from `hosts/thinkcentre/openclaw/.env`

4. In another terminal, approve the device:
   ```bash
   ssh thinkcentre "cd openclaw && docker compose run --rm openclaw-cli devices approve --latest"
   ```

5. Ctrl+C the node process on the Synology

## Persistence via Task Scheduler

Since Synology isn't NixOS, use DSM Task Scheduler for persistence:

1. Open DSM > Control Panel > Task Scheduler
2. Create > Triggered Task > User-defined script
3. Settings:
   - User: chris
   - Event: Boot-up
   - Task Settings > Run command:
     ```bash
     export PATH=/volume1/@appstore/Node.js_v20/usr/local/bin:/var/services/homes/chris/.npm-global/bin:$PATH
     export HOME=/var/services/homes/chris
     exec openclaw node run --host 192.168.0.12 --port 18789 --display-name synology \
       >> /var/log/openclaw-node.log 2>&1
     ```

## Updating

```bash
ssh synology "PATH=/volume1/@appstore/Node.js_v20/usr/local/bin:\$PATH npm update -g openclaw"
```

Then restart via DSM Task Scheduler (disable + enable the task) or reboot.

## Troubleshooting

```bash
# Check if running
ssh synology "ps aux | grep openclaw"

# Check logs
ssh synology "tail -50 /var/log/openclaw-node.log"

# Manual start for debugging
ssh synology "PATH=/volume1/@appstore/Node.js_v20/usr/local/bin:\$PATH openclaw node run --host 192.168.0.12 --port 18789 --display-name synology"
```
```

- [ ] **Step 4: Commit**

```bash
git add hosts/synology/
git commit -m "Add Synology openclaw node host setup documentation and scripts"
```

---

## Task 6: Deploy and verify

This task is manual - run through these steps to bring everything live.

- [ ] **Step 1: Let Syncthing sync config changes to ThinkCentre**

Wait for Syncthing to sync (usually <30 seconds). Verify:

```bash
ssh thinkcentre "cat ~/Projects/dotfiles/hosts/thinkcentre/openclaw/config/openclaw.json | grep assistant"
```

- [ ] **Step 2: Restart the openclaw gateway to pick up config changes**

```bash
ssh thinkcentre "cd ~/Projects/dotfiles/hosts/thinkcentre/openclaw && docker compose restart openclaw-gateway"
```

- [ ] **Step 3: Verify the bot responds on Telegram**

Send a message to the bot on Telegram. It should respond as a general assistant, not a fitness coach.

- [ ] **Step 4: Rebuild NixOS to install nodejs and the node host service**

```bash
ssh thinkcentre "cd ~/Projects/dotfiles && just rebuild"
```

- [ ] **Step 5: Bootstrap the ThinkCentre node host**

```bash
# Set up npm global prefix and install openclaw
ssh thinkcentre "npm config set prefix ~/.npm-global && npm install -g openclaw"

# Start node for initial pairing
ssh thinkcentre "OPENCLAW_GATEWAY_TOKEN=<token> openclaw node run --host 127.0.0.1 --port 18789 --display-name thinkcentre"

# In another terminal, approve the device
ssh thinkcentre "cd ~/Projects/dotfiles/hosts/thinkcentre/openclaw && docker compose run --rm openclaw-cli devices approve --latest"

# Ctrl+C the node, then start via systemd
ssh thinkcentre "sudo systemctl start openclaw-node && sudo systemctl status openclaw-node"
```

- [ ] **Step 6: Bootstrap the Synology node host**

```bash
# Run install script
ssh synology 'bash -s' < hosts/synology/openclaw-node/install.sh

# Approve device
ssh thinkcentre "cd ~/Projects/dotfiles/hosts/thinkcentre/openclaw && docker compose run --rm openclaw-cli devices approve --latest"

# Set up Task Scheduler persistence (manual via DSM UI - see README)
```

- [ ] **Step 7: Test exec approval flow**

Message the bot on Telegram: "Check disk space on the ThinkCentre"

Expected: The bot should show the command it wants to run (e.g. `df -h`) with approve/deny buttons in Telegram. Approve it and verify you get the output.

Then test: "How much storage is left on the Synology?"

Expected: Same approval flow, this time targeting the Synology node.

- [ ] **Step 8: Commit any final adjustments**

After testing, commit any tweaks needed.
