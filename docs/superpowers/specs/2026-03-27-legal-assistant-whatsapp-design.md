# Legal Assistant WhatsApp Agent for Dosar Maghieru

## Purpose

Give Claudia Tanul (the client in the dosar-maghieru legal case) a WhatsApp-based assistant that can answer questions about her case, receive documents and voice messages, perform legal lookups, and triage new information into the existing case management system -- all while maintaining the strict data integrity rules established in the project's CLAUDE.md.

Christian reviews all changes via GitHub PRs before anything reaches the main branch.

## Architecture

A new, fully independent OpenClaw gateway instance (`openclaw-legal`) on thinkcentre, separate from the fitness-coach instance. It runs the `legal-assistant` agent bound to WhatsApp and operates on a git clone of `scriptogre/dosar-maghieru` inside the container.

```
Claudia (WhatsApp) → OpenClaw gateway → legal-assistant agent (Sonnet 4.6)
                                              │
                                              ├── Git clone of dosar-maghieru (read FAPTE.md, docs)
                                              ├── Gemini API (PDF transcription, deep research)
                                              ├── legislatie.just.ro (legal lookups)
                                              └── GitHub API (push branches, create PRs)
```

### Data flow

- Factual questions → agent reads FAPTE.md and document .md files, answers directly
- Simple legal lookups → agent searches legislatie.just.ro, answers with link/citation
- Complex legal questions → Gemini Deep Research, shares findings with citations
- New PDF received → Gemini API transcription → saves .pdf + .md → commits to branch → PR
- New info from conversation → drafts updates to FAPTE or STRATEGIE → commits to branch → PR
- Large/complex PDFs that fail → tells Claudia that Christian needs to help with this one
- Duplicate documents → acknowledges naturally without making Claudia feel redundant
- Voice messages → transcribed by OpenClaw Whisper (built-in), treated as text input

## Agent Identity & Personality

**Agent ID**: `legal-assistant`
**Model**: `anthropic/claude-sonnet-4-6`
**Language**: Romanian (all communication)
**Channel**: WhatsApp

### Personality (SOUL.md)

- Warm, clear, assuring, pragmatic -- a steady pillar for Claudia
- Acknowledges emotions briefly, then steers toward facts and actionable next steps
- Never uses legal jargon without explaining it simply
- Never condescending or patronizing
- Transparent when performing lookups ("Verific în legislație...") and provides links so Claudia can check herself
- Does not surface internal plumbing (PRs, branches, reviews) to Claudia -- she just talks to a competent assistant
- Concise -- WhatsApp messages, not essays

### User context (USER.md)

- Claudia Tanul, client and heir of Vlad Magheru (deceased 16.10.2025)
- Communicates via WhatsApp in Romanian
- May send voice messages, PDFs, photos of documents
- May repeat information or send the same documents multiple times
- May express emotions and opinions about the case -- these go to STRATEGIE.md, never FAPTE.md
- Christian (son) and his brother handle legal strategy and review all changes

## Case Knowledge (Skill: `dosar-maghieru`)

The skill does NOT duplicate the project's CLAUDE.md. It points the agent to read `/home/node/dosar-maghieru/CLAUDE.md` for all case rules and conventions. The skill only adds operational context specific to this agent:

- You operate on a git clone at `/home/node/dosar-maghieru/`
- Run `git checkout main && git pull` before reading any files to ensure freshness
- Never commit to main. Create branches named `claudia/<descriptive-topic>` (e.g., `claudia/expertiza-ionita`, `claudia/plangere-penala-update`)
- Use the GitHub API (scoped token) to push branches and create PRs
- PR body must include: what Claudia said/sent, what the agent understood, what files changed and how
- Batch related changes into one PR by topic (don't flood with one PR per message)
- Before processing a new PDF, check existing filenames and content for duplicates
- If any git operation fails unexpectedly, delete the local clone and re-clone from GitHub -- no data is lost since all work is pushed to remote
- When citing legislatie.just.ro in conversation, always include the direct link so Claudia can verify
- When something is too complex or beyond your capabilities, tell Claudia naturally and let her know Christian will help

## Gemini Integration (Skill: `gemini-transcription`)

### PDF Transcription

**Critical: the agent must NEVER read/load PDF files itself.** PDFs are passed directly to Gemini for transcription. The agent only reads the resulting .md transcription. This prevents blowing out the agent's context window and wasting tokens.

1. Claudia sends a PDF via WhatsApp
2. Agent asks for context if not obvious (source, date, court)
3. Saves the PDF to the git clone with proper naming (from CLAUDE.md conventions)
4. Passes the PDF file directly to Gemini API for transcription (agent does not open/read the PDF)
5. Gemini returns structured markdown; agent saves it as .md alongside the PDF
6. Agent reads the .md transcription to understand the document and extract new facts
7. For large PDFs: if Gemini fails or returns errors, tells Claudia that Christian needs to handle it
8. Commits .pdf + .md to branch, creates PR

### Deep Research

1. Agent identifies a question that needs multi-angle legal research
2. Formulates a research prompt following the CLAUDE.md rules
3. Calls Gemini API with the prompt
4. Shares findings with Claudia naturally, including citations and links
5. Includes results in the PR for Christian's review before updating LEGE.md

## WhatsApp Channel Configuration

```json
{
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
}
```

- Allowlisted to Claudia's number (+40744755292)
- Groups enabled for a family group (Claudia, Christian, brother) -- group ID added once created
- Ack reaction (👀) provides immediate feedback that the message was received
- Linked via a separate WhatsApp number (prepaid SIM or eSIM)

## Agent Binding

```json
{
  "agentId": "legal-assistant",
  "match": {
    "channel": "whatsapp"
  }
}
```

## Infrastructure

### Fully separate OpenClaw instance

The legal-assistant runs as its own OpenClaw gateway container, completely independent from the fitness-coach. OpenClaw presents all skills in its config directory to every agent, so sharing a gateway would leak irrelevant skills between agents.

```
hosts/thinkcentre/
├── openclaw/               # fitness-coach (existing, untouched)
└── openclaw-legal/          # legal-assistant (new, fully independent)
    ├── .env
    ├── docker-compose.yml
    ├── config/
    │   ├── openclaw.json
    │   ├── skills/
    │   │   ├── dosar-maghieru/SKILL.md
    │   │   └── gemini-transcription/SKILL.md
    │   └── cron/jobs.json
    └── workspace/
        ├── IDENTITY.md
        ├── SOUL.md
        ├── USER.md
        ├── AGENTS.md
        └── MEMORY.md
```

### Docker setup

- Image: `ghcr.io/openclaw/openclaw:latest`
- Gateway port: `18790` (different from fitness-coach's `18789`)
- Persistent named volume for the git clone (mounted at `/home/node/dosar-maghieru/`)
- Shares the `proxy` Docker network (for Caddy, if needed)

### Environment variables

- `ANTHROPIC_API_KEY` -- for Sonnet 4.6
- `GEMINI_API_KEY` -- for PDF transcription and deep research
- `GITHUB_TOKEN` -- fine-grained PAT scoped to `scriptogre/dosar-maghieru` only (Contents + Pull Requests write)
- `GROQ_API_KEY` -- for Whisper voice transcription (reuse existing key)
- `OPENAI_API_KEY` -- for TTS/STT fallback (reuse existing key)

### Security

- No SSH access -- the legal-assistant does NOT have the host-ssh skill
- Scoped GitHub token -- one repo only, limited permissions
- Git clone isolated inside container -- cannot affect Syncthing-synced working copy or host filesystem
- Never commits to main -- branch + PR only
- If git state gets corrupted, delete and re-clone (no data loss)

## Agent Workflow

### On every interaction

1. `git checkout main && git pull` (quiet, in background)
2. Read FAPTE.md into context

### Text message from Claudia

- Ground response in FAPTE.md and relevant document .md files
- Answer factually from existing docs when possible
- New facts → draft FAPTE.md update on branch
- Opinions/emotions → draft STRATEGIE.md update on branch
- Repeated info → incorporate naturally ("Da, asta se potrivește cu ce avem deja notat")
- Simple legal question → lookup on legislatie.just.ro, share finding with link
- Complex legal question → Gemini deep research, share findings with citations

### PDF from Claudia

- Ask for context if not obvious
- Check for duplicates against existing files
- Name and save following project conventions
- Transcribe via Gemini API
- Review transcription, extract new facts
- Commit to branch, create PR
- Tell Claudia what the document contains and what it means

### Voice message from Claudia

- Transcribed automatically by OpenClaw Whisper
- Treated as text message
- Raw transcription preserved in PR for reference

### PR creation

- Branch: `claudia/<descriptive-topic>` (short, clear, no dates)
- Smart batching: messages about the same topic go into one PR
- PR title in Romanian, concise
- Christian reviews on GitHub, refines with Claude Code + Opus if needed, merges

**PR body template:**

```markdown
## Sursă

Ce a trimis/spus Claudia (rezumat scurt, cu citat direct dacă e relevant).

## Ce am înțeles

Interpretarea agentului: ce fapte noi, ce opinii, ce documente.

## Modificări

- `FAPTE.md` -- [ce s-a adăugat/modificat și unde]
- `01-Partaj/2026-XX-XX_Nume_Document.md` -- [transcriere nouă]
- etc.

## De verificat

Orice lucru despre care agentul nu e sigur sau care necesită atenție.
```

## Notifications

GitHub's built-in notification system. Christian sees PRs on the repo and reviews them. No cross-agent notifications needed.

## Dependencies & Setup Checklist

1. Separate WhatsApp number (prepaid SIM or eSIM)
2. Fine-grained GitHub PAT scoped to `scriptogre/dosar-maghieru`
3. Gemini API key
4. Anthropic API key (can reuse existing)
5. Create `hosts/thinkcentre/openclaw-legal/` directory structure
6. Write docker-compose.yml, .env, openclaw.json
7. Write agent workspace files (IDENTITY.md, SOUL.md, USER.md, AGENTS.md, MEMORY.md)
8. Write skills (dosar-maghieru/SKILL.md, gemini-transcription/SKILL.md)
9. Install WhatsApp plugin in the new instance (`openclaw plugins install @openclaw/whatsapp`)
10. Link WhatsApp via QR (`openclaw channels login --channel whatsapp`)
11. Initial git clone of dosar-maghieru inside container
12. Create family WhatsApp group (Claudia, Christian, brother)
13. Test: send message from Claudia's number, verify agent responds
14. Test: send PDF, verify Gemini transcription + PR creation
