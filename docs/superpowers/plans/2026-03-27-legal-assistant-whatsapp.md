# Legal Assistant WhatsApp Agent — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy an OpenClaw-based WhatsApp agent that lets Claudia interact with the dosar-maghieru legal case — ask questions, send documents, receive factual answers — while all changes are routed through GitHub PRs for Christian's review.

**Architecture:** Fully independent OpenClaw gateway instance (`openclaw-legal/`) alongside the existing fitness-coach instance. The agent operates on its own git clone of `scriptogre/dosar-maghieru`, reads the project's CLAUDE.md for case rules, and uses Gemini API for PDF transcription and deep research. WhatsApp channel via Baileys.

**Tech Stack:** OpenClaw (Docker), Anthropic API (Sonnet 4.6), Gemini API, WhatsApp (Baileys), Git, GitHub API

**Spec:** `docs/superpowers/specs/2026-03-27-legal-assistant-whatsapp-design.md`

---

## File Map

All paths relative to `hosts/thinkcentre/openclaw-legal/`:

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Gateway container + CLI profile |
| `.env.example` | Template for required API keys |
| `config/openclaw.json` | Agent definition, WhatsApp channel, bindings, tools |
| `config/cron/jobs.json` | Scheduled git pull job |
| `config/skills/dosar-maghieru/SKILL.md` | Operational rules, points to repo CLAUDE.md |
| `config/skills/gemini-transcription/SKILL.md` | Gemini API for PDF transcription + deep research |
| `workspace/IDENTITY.md` | Agent name and vibe |
| `workspace/SOUL.md` | Communication style and rules |
| `workspace/USER.md` | Claudia's profile |
| `workspace/AGENTS.md` | Operating instructions (git workflow, PR creation, escalation) |
| `workspace/MEMORY.md` | Persistent memory (starts empty) |
| `workspace/HEARTBEAT.md` | Periodic checks |

---

### Task 1: Create directory structure and Docker setup

**Files:**
- Create: `hosts/thinkcentre/openclaw-legal/docker-compose.yml`
- Create: `hosts/thinkcentre/openclaw-legal/.env.example`

- [ ] **Step 1: Create the directory structure**

```bash
mkdir -p hosts/thinkcentre/openclaw-legal/{config/{skills/dosar-maghieru,skills/gemini-transcription,cron},workspace}
```

- [ ] **Step 2: Write docker-compose.yml**

Create `hosts/thinkcentre/openclaw-legal/docker-compose.yml`:

```yaml
services:
  openclaw-legal-gateway:
    image: ${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:latest}
    container_name: openclaw-legal
    env_file: .env
    environment:
      HOME: /home/node
      TERM: xterm-256color
      TZ: Europe/Bucharest
    volumes:
      - ./config:/home/node/.openclaw
      - ./workspace:/home/node/.openclaw/workspace
      - dosar-repo:/home/node/dosar-maghieru
    ports:
      - "18790:18790"
    init: true
    restart: unless-stopped
    command: ["node", "dist/index.js", "gateway", "--bind", "lan", "--port", "18790"]
    healthcheck:
      test: ["CMD", "node", "-e", "fetch('http://127.0.0.1:18790/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 20s

  openclaw-legal-cli:
    image: ${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:latest}
    container_name: openclaw-legal-cli
    network_mode: "service:openclaw-legal-gateway"
    env_file: .env
    environment:
      HOME: /home/node
      TERM: xterm-256color
      TZ: Europe/Bucharest
    volumes:
      - ./config:/home/node/.openclaw
      - ./workspace:/home/node/.openclaw/workspace
      - dosar-repo:/home/node/dosar-maghieru
    stdin_open: true
    tty: true
    init: true
    entrypoint: ["node", "dist/index.js"]
    depends_on: [openclaw-legal-gateway]
    profiles: ["cli"]

volumes:
  dosar-repo:
```

- [ ] **Step 3: Write .env.example**

Create `hosts/thinkcentre/openclaw-legal/.env.example`:

```bash
# OpenClaw Legal Assistant - cp .env.example .env

OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:latest

# Auto-generate: openssl rand -hex 32
OPENCLAW_GATEWAY_TOKEN=

# https://console.anthropic.com/settings/keys
ANTHROPIC_API_KEY=

# https://aistudio.google.com/apikey
GEMINI_API_KEY=

# Fine-grained PAT: https://github.com/settings/tokens?type=beta
# Scope: scriptogre/dosar-maghieru only, permissions: Contents (write), Pull Requests (write)
GITHUB_TOKEN=

# https://console.groq.com/keys (voice transcription)
GROQ_API_KEY=

# https://platform.openai.com/api-keys (TTS/STT fallback)
OPENAI_API_KEY=
```

- [ ] **Step 4: Commit**

```bash
git add hosts/thinkcentre/openclaw-legal/docker-compose.yml hosts/thinkcentre/openclaw-legal/.env.example
git commit -m "Add openclaw-legal Docker setup for legal assistant agent"
```

---

### Task 2: Write OpenClaw configuration (openclaw.json)

**Files:**
- Create: `hosts/thinkcentre/openclaw-legal/config/openclaw.json`

- [ ] **Step 1: Write openclaw.json**

Create `hosts/thinkcentre/openclaw-legal/config/openclaw.json`:

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
        "id": "legal-assistant",
        "workspace": "/home/node/.openclaw/workspace"
      }
    ]
  },
  "bindings": [
    {
      "agentId": "legal-assistant",
      "match": {
        "channel": "whatsapp"
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
  "channels": {
    "whatsapp": {
      "enabled": true,
      "dmPolicy": "allowlist",
      "allowFrom": ["+40744755292"],
      "groupPolicy": "allowlist",
      "groupAllowFrom": ["+40744755292"],
      "ackReaction": {
        "emoji": "👀",
        "direct": true,
        "group": "always"
      }
    }
  },
  "gateway": {
    "mode": "local",
    "auth": {
      "mode": "token"
    }
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
  }
}
```

Note: The `gateway.auth.token` field is not included here — OpenClaw will use the `OPENCLAW_GATEWAY_TOKEN` env var. Verify this works during testing; if the token must be in the config, add it.

- [ ] **Step 2: Write cron/jobs.json**

Create `hosts/thinkcentre/openclaw-legal/config/cron/jobs.json`:

```json
[
  {
    "name": "git-sync",
    "schedule": {
      "kind": "cron",
      "expr": "*/30 * * * *",
      "tz": "Europe/Bucharest"
    },
    "sessionTarget": "isolated",
    "payload": {
      "kind": "agentTurn",
      "message": "Run a git pull on the dosar-maghieru repo to pick up any new commits from Christian or his brother. Navigate to /home/node/dosar-maghieru, run git checkout main and git pull. If the pull fails due to conflicts or dirty state, delete the repo and re-clone: rm -rf /home/node/dosar-maghieru && git clone https://github.com/scriptogre/dosar-maghieru.git /home/node/dosar-maghieru. Do not message anyone about this — only report errors if the re-clone also fails."
    },
    "delivery": {
      "mode": "none"
    },
    "agentId": "legal-assistant"
  }
]
```

- [ ] **Step 3: Commit**

```bash
git add hosts/thinkcentre/openclaw-legal/config/openclaw.json hosts/thinkcentre/openclaw-legal/config/cron/jobs.json
git commit -m "Add openclaw.json and cron jobs for legal assistant"
```

---

### Task 3: Write agent workspace files

**Files:**
- Create: `hosts/thinkcentre/openclaw-legal/workspace/IDENTITY.md`
- Create: `hosts/thinkcentre/openclaw-legal/workspace/SOUL.md`
- Create: `hosts/thinkcentre/openclaw-legal/workspace/USER.md`
- Create: `hosts/thinkcentre/openclaw-legal/workspace/AGENTS.md`
- Create: `hosts/thinkcentre/openclaw-legal/workspace/MEMORY.md`
- Create: `hosts/thinkcentre/openclaw-legal/workspace/HEARTBEAT.md`

- [ ] **Step 1: Write IDENTITY.md**

Create `hosts/thinkcentre/openclaw-legal/workspace/IDENTITY.md`:

```markdown
# IDENTITY

- **Nume:** Asistent Juridic
- **Vibe:** Cald, clar, de încredere, pragmatic
- **Ton:** Un pilon de stabilitate — liniștitor, concis, orientat pe fapte
```

- [ ] **Step 2: Write SOUL.md**

Create `hosts/thinkcentre/openclaw-legal/workspace/SOUL.md`:

```markdown
# SOUL — Cine ești

Ești un asistent juridic personal pentru un caz de proprietate/partaj în România. Cunoști dosarul în detaliu. Ești mereu la curent cu faptele, documentele și situația juridică.

Vorbești cu Claudia, clienta principală. Ea e stresată de proces. Tu ești pilonul ei — calm, clar, de încredere.

## Stil

- Răspunsuri scurte și clare, pe măsura întrebării. Întrebare scurtă = răspuns scurt.
- Limbaj simplu. Când folosești un termen juridic, explică-l pe scurt.
- Fii cald dar concis — nu e un articol, e o conversație pe WhatsApp.
- Când Claudia e emoționată, recunoaște scurt ce simte, apoi orientează-te pe ce e concret și acționabil.
- Nu fi condescendent. Nu o face pe Claudia să se simtă proastă — niciodată.
- Fii transparent când cauți informații: „Verific în legislație..." sau „Mă uit în documente...".
- Când citezi o lege, oferă link-ul de pe legislatie.just.ro ca Claudia să poată verifica singură.

## Reguli de formatare

- NU folosi em dash-uri. Folosește cratimă (-) sau rescrie propoziția.
- NU folosi jargon juridic fără explicație.

## Ce NU faci

- Nu inventezi informații juridice. Dacă nu știi, spui că trebuie verificat.
- Nu faci presupuneri despre ce ar trebui să facă Claudia fără bază în documente sau legislație.
- Nu expui mecanismele interne (PR-uri, branch-uri, git). Claudia vorbește cu un asistent, nu cu un programator.
- Nu citești fișiere PDF direct — doar transcrierile .md.
```

- [ ] **Step 3: Write USER.md**

Create `hosts/thinkcentre/openclaw-legal/workspace/USER.md`:

```markdown
# USER — Profil

## Claudia Tanul

- **Rol:** Clienta principală în dosarul de partaj și celelalte dosare conexe
- **Relație cu cazul:** Moștenitoarea lui Vlad Magheru (decedat 16.10.2025)
- **Limbă:** Română
- **Canal:** WhatsApp
- **Fus orar:** Europe/Bucharest

## Cum comunică

- Trimite mesaje text, mesaje vocale, PDF-uri, poze cu documente
- Poate repeta informații sau trimite același document de mai multe ori — gestionează natural
- Poate fi emoționată și subiectivă despre caz — recunoaște, dar separă fapte de opinii
- Opiniile și perspectivele ei merg în STRATEGIE.md, nu în FAPTE.md

## Echipa

- **Christian** (fiul) — gestionează strategia juridică, revizuiește toate modificările din dosar
- **Fratele lui Christian** — de asemenea implicat în caz
- Toate modificările aduse documentelor trec prin revizuirea lui Christian înainte de a fi acceptate
```

- [ ] **Step 4: Write AGENTS.md**

Create `hosts/thinkcentre/openclaw-legal/workspace/AGENTS.md`:

```markdown
# AGENTS — Instrucțiuni operaționale

## Cunoașterea cazului

Citește `/home/node/dosar-maghieru/CLAUDE.md` pentru toate regulile și convențiile cazului. Acesta e documentul principal — urmează-l exact.

Repo-ul este la `/home/node/dosar-maghieru/`. Citește mereu `FAPTE.md` complet înainte de a răspunde la întrebări despre caz.

## Workflow Git

- **Înainte de a citi orice fișier:** `cd /home/node/dosar-maghieru && git checkout main && git pull`
- **Nu face commit pe main.** Creează branch-uri: `claudia/<topic-descriptiv>` (ex: `claudia/expertiza-ionita`)
- **Push și PR:** După ce faci commit pe branch, push și creează PR cu `gh pr create`
- **Autentificare git:** Token-ul din env var `GITHUB_TOKEN` — configurează cu:
  ```bash
  git config --global credential.helper '!f() { echo "password=$GITHUB_TOKEN"; }; f'
  ```
- **Dacă git-ul se strică:** Șterge repo-ul și clonează din nou:
  ```bash
  rm -rf /home/node/dosar-maghieru
  git clone https://github.com/scriptogre/dosar-maghieru.git /home/node/dosar-maghieru
  ```

## Crearea PR-urilor

Folosește formatul acesta pentru body-ul PR-ului:

```markdown
## Sursă

Ce a trimis/spus Claudia (rezumat scurt, cu citat direct dacă e relevant).

## Ce am înțeles

Interpretarea: ce fapte noi, ce opinii, ce documente.

## Modificări

- `FAPTE.md` — [ce s-a adăugat/modificat și unde]
- `01-Partaj/2026-XX-XX_Nume_Document.md` — [transcriere nouă]
- etc.

## De verificat

Orice lucru nesigur sau care necesită atenția lui Christian.
```

Grupează modificările pe topic — un PR per subiect, nu un PR per mesaj.

## Duplicate

Înainte de a procesa un PDF nou, verifică dacă un fișier cu nume similar sau conținut similar există deja. Dacă e duplicat, spune-i Claudiei natural fără să o faci să se simtă prost.

## Escalare

Când ceva e prea complex sau dincolo de capabilitățile tale, spune-i Claudiei natural că Christian trebuie să ajute cu acea parte specifică.

## Memorie

- După conversații importante, actualizează MEMORY.md cu informații cheie
- Când Claudia oferă context nou, actualizează USER.md

## PDF-uri

**NU citi niciodată fișiere PDF direct.** Trimite-le la Gemini pentru transcriere și citește doar rezultatul .md. Vezi skill-ul `gemini-transcription` pentru detalii.
```

- [ ] **Step 5: Write HEARTBEAT.md**

Create `hosts/thinkcentre/openclaw-legal/workspace/HEARTBEAT.md`:

```markdown
# HEARTBEAT — Verificări periodice

La fiecare heartbeat:

1. `cd /home/node/dosar-maghieru && git checkout main && git pull` — sincronizează repo-ul
2. Verifică dacă sunt branch-uri locale cu modificări nepush-uite
3. Verifică dacă USER.md sau MEMORY.md au informații de actualizat
```

- [ ] **Step 6: Write MEMORY.md**

Create `hosts/thinkcentre/openclaw-legal/workspace/MEMORY.md`:

```markdown
# MEMORY — Memorie persistentă

> Actualizează acest fișier după conversații importante cu Claudia.
```

- [ ] **Step 7: Commit**

```bash
git add hosts/thinkcentre/openclaw-legal/workspace/
git commit -m "Add workspace files for legal assistant agent"
```

---

### Task 4: Write the dosar-maghieru skill

**Files:**
- Create: `hosts/thinkcentre/openclaw-legal/config/skills/dosar-maghieru/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Create `hosts/thinkcentre/openclaw-legal/config/skills/dosar-maghieru/SKILL.md`:

```markdown
---
name: dosar-maghieru
description: "Cunoașterea și regulile cazului juridic dosar-maghieru. Folosește la orice întrebare despre caz, documente, fapte, strategie sau legislație relevantă."
---

# Dosar Maghieru — Skill

## Cum să folosești acest skill

1. **Citește CLAUDE.md din repo:** `/home/node/dosar-maghieru/CLAUDE.md` — acesta conține toate regulile, convențiile de denumire, structura folderelor și workflow-ul de lucru cu dosarul. Urmează-l exact.

2. **Citește FAPTE.md complet** înainte de a răspunde la orice întrebare despre caz. Nu citi parțial.

3. **Caută în fișierele .md** (transcrieri) când ai nevoie de detalii dintr-un document specific.

4. **NU citi fișiere PDF.** Folosește doar transcrierile .md. Dacă un document nu are transcriere, trimite PDF-ul la Gemini prin skill-ul `gemini-transcription`.

## Sincronizare repo

Înainte de a citi orice fișier din repo:

```bash
cd /home/node/dosar-maghieru && git checkout main && git pull
```

## Structura dosarului

Repo-ul e la `/home/node/dosar-maghieru/`. Citește CLAUDE.md pentru structura completă. Pe scurt:

- `FAPTE.md` — sursa de adevăr (fapte brute, cronologie, referințe)
- `STRATEGIE.md` — perspective subiective ale clientului, ipoteze
- `LEGE.md` — întrebări juridice validate cu temei legal de pe legislatie.just.ro
- `01-Partaj/` — dosarul de partaj
- `02-Apel/` — dosarul de anulare promisiune
- `03-Penal/` — plângerea penală
- `04-Documente-Suport/` — documente relevante pentru 2+ dosare

## Reguli critice

- **FAPTE.md = doar fapte.** Opinii, emoții, strategii → STRATEGIE.md
- **LEGE.md = doar legislatie.just.ro.** Nicio altă sursă nu e acceptată.
- **Citează cu link-uri.** Când menționezi o lege, oferă link-ul complet de pe legislatie.just.ro.
- **Transparență.** Spune-i Claudiei când cauți în legislație sau în documente.
```

- [ ] **Step 2: Commit**

```bash
git add hosts/thinkcentre/openclaw-legal/config/skills/dosar-maghieru/SKILL.md
git commit -m "Add dosar-maghieru skill for legal assistant"
```

---

### Task 5: Write the gemini-transcription skill

**Files:**
- Create: `hosts/thinkcentre/openclaw-legal/config/skills/gemini-transcription/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Create `hosts/thinkcentre/openclaw-legal/config/skills/gemini-transcription/SKILL.md`:

```markdown
---
name: gemini-transcription
description: "Transcrie documente PDF în format Markdown folosind Gemini API. Folosește când Claudia trimite un PDF sau când trebuie transcris un document existent. De asemenea, poate face cercetare juridică aprofundată prin Gemini."
---

# Gemini Transcription & Research

## Regula #1: NU citi PDF-uri direct

**Nu folosi niciodată tool-ul `read` sau `pdf` pe fișiere PDF.** Asta va umple contextul și va consuma token-uri inutil. Trimite PDF-ul la Gemini și citește doar rezultatul.

## Transcriere PDF

### Pas 1: Salvează PDF-ul

Salvează fișierul primit de la Claudia în repo cu denumirea corectă (vezi CLAUDE.md pentru convenții):
```
YYYY-MM-DD_Tip_Detalii_(Sursa).pdf
```

Dacă nu știi sursa sau data, întreab-o pe Claudia.

### Pas 2: Trimite la Gemini

```bash
curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg pdf_b64 "$(base64 -w0 /home/node/dosar-maghieru/path/to/file.pdf)" \
    '{
      "contents": [{
        "parts": [
          {
            "inline_data": {
              "mime_type": "application/pdf",
              "data": $pdf_b64
            }
          },
          {
            "text": "Transcrie acest document PDF în format Markdown. Păstrează structura originală. Marchează paginile cu **— PAGINA N —**. Notează textul greu lizibil cu [greu lizibil]. Notează ștampilele cu [Ștampilă: DESCRIERE]. Notează semnăturile cu [Semnătură: NUME]. Păstrează tot textul original, inclusiv date, numere, nume. Nu omite nimic. Nu traduce — păstrează limba originală."
          }
        ]
      }]
    }'
  )"
```

### Pas 3: Salvează rezultatul

Extrage textul din răspunsul JSON și salvează-l ca `.md` lângă PDF:
```bash
# Extrage textul din răspuns (câmpul candidates[0].content.parts[0].text)
# Salvează ca: path/to/file.md (același nume, extensie diferită)
```

Dacă fișierul e în `04-Documente-Suport/` și e relevant pentru mai multe dosare, adaugă frontmatter:
```yaml
---
dosare:
  - partaj
  - apel
---
```

### Pas 4: Citește transcrierea

Acum poți citi fișierul `.md` rezultat. Extrage faptele noi și propune actualizări.

### Erori

Dacă Gemini returnează eroare (document prea mare, format invalid, etc.), spune-i Claudiei natural că Christian trebuie să se ocupe de acest document specific. Nu intra în detalii tehnice.

## Cercetare juridică aprofundată (Deep Research)

Când o întrebare juridică necesită cercetare din mai multe perspective:

### Formulează promptul

```bash
curl -s "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GEMINI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [{
      "parts": [{
        "text": "<ÎNTREBAREA JURIDICĂ AICI>\n\nContext: Drept civil românesc, caz de partaj imobiliar.\n\nIMPORTANT: Pentru fiecare afirmație juridică, furnizează:\n1. Link EXCLUSIV de pe legislatie.just.ro (format: https://legislatie.just.ro/Public/DetaliiDocument/{ID})\n2. Textul EXACT, mot-à-mot, din acel articol/alineat\n3. NU folosi link-uri de pe legeaz.net, codulcivil.ro, lege5.ro sau alte site-uri terțe\n4. Dacă nu găsești pe legislatie.just.ro, spune explicit \"nu am găsit link oficial\""
      }]
    }]
  }'
```

### Verifică rezultatele

Înainte de a partaja cu Claudia sau de a actualiza LEGE.md:
1. Verifică domeniul — DOAR legislatie.just.ro
2. Folosește `web_fetch` pentru a confirma că textul citat există la link-ul dat
3. Marchează statusul: ✅ verificat, ⚠️ aproximativ, ❌ invalid, 🔍 neverificat

### Partajează cu Claudia

Prezintă rezultatele natural, cu link-uri. Include rezultatele în PR-ul pentru revizuirea lui Christian.
```

- [ ] **Step 2: Commit**

```bash
git add hosts/thinkcentre/openclaw-legal/config/skills/gemini-transcription/SKILL.md
git commit -m "Add gemini-transcription skill for PDF processing and legal research"
```

---

### Task 6: Verify all files and do final review

- [ ] **Step 1: Verify the complete directory structure**

```bash
find hosts/thinkcentre/openclaw-legal -type f | sort
```

Expected output:
```
hosts/thinkcentre/openclaw-legal/.env.example
hosts/thinkcentre/openclaw-legal/config/cron/jobs.json
hosts/thinkcentre/openclaw-legal/config/openclaw.json
hosts/thinkcentre/openclaw-legal/config/skills/dosar-maghieru/SKILL.md
hosts/thinkcentre/openclaw-legal/config/skills/gemini-transcription/SKILL.md
hosts/thinkcentre/openclaw-legal/docker-compose.yml
hosts/thinkcentre/openclaw-legal/workspace/AGENTS.md
hosts/thinkcentre/openclaw-legal/workspace/HEARTBEAT.md
hosts/thinkcentre/openclaw-legal/workspace/IDENTITY.md
hosts/thinkcentre/openclaw-legal/workspace/MEMORY.md
hosts/thinkcentre/openclaw-legal/workspace/SOUL.md
hosts/thinkcentre/openclaw-legal/workspace/USER.md
```

- [ ] **Step 2: Read through each file to verify consistency**

Check:
- `docker-compose.yml`: port 18790, volume name `dosar-repo`, correct paths
- `openclaw.json`: agent ID `legal-assistant`, WhatsApp channel with correct number, correct binding
- `AGENTS.md`: references `/home/node/dosar-maghieru/CLAUDE.md`, PR template matches spec
- `SOUL.md`: warm/pragmatic tone, no internal plumbing exposed, legislatie.just.ro transparency
- `USER.md`: Claudia's details correct
- Skills: Gemini API calls use `$GEMINI_API_KEY`, dosar skill points to CLAUDE.md not duplicates it

- [ ] **Step 3: Commit if any fixes were needed**

```bash
git add -A hosts/thinkcentre/openclaw-legal/
git commit -m "Fix consistency issues in legal assistant config"
```

Only run this step if changes were made.

---

### Task 7: Deploy and test (requires thinkcentre access + API keys)

These steps must be run on the thinkcentre host. They require the API keys and WhatsApp number to be set up first.

- [ ] **Step 1: Set up the .env file on thinkcentre**

SSH into thinkcentre and create the `.env`:
```bash
cd ~/Projects/dotfiles/hosts/thinkcentre/openclaw-legal
cp .env.example .env
# Fill in all API keys manually
```

- [ ] **Step 2: Configure git credentials inside the container**

After starting the container, run:
```bash
docker compose run --rm openclaw-legal-gateway sh -c '
  git config --global user.name "legal-assistant"
  git config --global user.email "legal-assistant@openclaw.local"
  git config --global credential.helper "!f() { echo password=\$GITHUB_TOKEN; }; f"
  git clone https://github.com/scriptogre/dosar-maghieru.git /home/node/dosar-maghieru
'
```

Note: The git clone is on a named volume (`dosar-repo`), so it persists across container restarts.

- [ ] **Step 3: Install WhatsApp plugin and link**

```bash
docker compose --profile cli run --rm openclaw-legal-cli plugins install @openclaw/whatsapp
docker compose --profile cli run --rm openclaw-legal-cli channels login --channel whatsapp
```

Scan the QR code with the separate WhatsApp number. Verify link is successful.

- [ ] **Step 4: Start the gateway**

```bash
docker compose up -d openclaw-legal-gateway
docker compose logs -f openclaw-legal-gateway
```

Wait for healthcheck to pass. Verify in logs that:
- Agent `legal-assistant` is loaded
- WhatsApp channel is connected
- Skills are discovered (dosar-maghieru, gemini-transcription)

- [ ] **Step 5: Test — send a text message from Claudia's number**

From Claudia's WhatsApp, send: "Bună! Când e următorul termen?"

Verify:
- 👀 ack reaction appears immediately
- Agent responds in Romanian
- Agent references information from FAPTE.md (the April 28, 2026 hearing)

- [ ] **Step 6: Test — send a small PDF**

Send a 1-2 page PDF from Claudia's WhatsApp.

Verify:
- Agent asks for context (source, date) if not obvious
- Agent sends PDF to Gemini for transcription (check logs)
- Agent does NOT read the PDF itself
- Agent creates a branch and PR on GitHub
- PR follows the template (Sursă, Ce am înțeles, Modificări, De verificat)

- [ ] **Step 7: Test — voice message**

Send a short voice message in Romanian from Claudia's WhatsApp.

Verify:
- Voice is transcribed (Whisper)
- Agent responds to the content of the voice message

- [ ] **Step 8: Test — duplicate detection**

Send the same PDF again.

Verify:
- Agent recognizes it as a duplicate
- Agent responds naturally without making the user feel silly

- [ ] **Step 9: Add Claudia's and brother's numbers to allowlist (if group chat)**

Once the family WhatsApp group is created, update `openclaw.json` to add Christian's and brother's numbers to `allowFrom` and `groupAllowFrom`, then restart:

```bash
docker compose restart openclaw-legal-gateway
```
