* Do not include the fact that a commit was made by/with Claude Code.
* Do not include anything about Claude Code in your commit messages.
* **NEVER use the Explore agent.** Always search/read files directly using Bash (grep, find), Read, and Grep tools instead of spawning Explore subagents.

## Homelab — ThinkCentre m80q Gen 4

* Available via `ssh thinkcentre`. Managed by **NixOS**.
* **All changes MUST be declarative** via `~/Projects/dotfiles/hosts/thinkcentre/`. NEVER make imperative changes on the ThinkCentre.
* Read `~/Projects/dotfiles/hosts/thinkcentre/` locally on the Mac to understand the setup.
* `~/Projects` on the Mac syncs bidirectionally to `~/Projects` on the ThinkCentre via **Syncthing**.
  * ⚠️ **NEVER delete files inside `~/Projects/dotfiles/hosts/thinkcentre/`** — deletions propagate via Syncthing and destroy live data on the server. To exclude files from git, add them to `.gitignore` instead.
* **When editing files for the ThinkCentre, prefer editing directly on the ThinkCentre** (`ssh thinkcentre`) and let Syncthing sync back to the Mac.
* **Caddy** runs in Docker with a custom build (Cloudflare DNS TLS plugin). Router port-forwards 80/443 to the ThinkCentre.
  * Caddy does **NOT** auto-reload on Caddyfile changes. You must run `just` inside the caddy folder (`~/Projects/dotfiles/hosts/thinkcentre/caddy/`) to reload in-place with zero downtime.
  * Do NOT use `docker exec caddy caddy reload` — use the `just` command.
  * The Caddyfile is bind-mounted as a single file. If you edit it with `sed -i` or any tool that atomically renames, Caddy keeps the old inode and `just` reload won't see changes — follow up with `docker compose restart caddy` in that case.
* After any significant dotfiles changes, **remind/ask me to commit & push** so we don't have uncommitted changes.

## Secrets — 1Password CLI

Access secrets via `op` CLI without reading them yourself. Pattern:

```bash
# Find items (safe - no secrets shown)
op item list | grep -i "keyword"

# Get field labels only (safe)
op item get ITEM_ID --format json | node -e "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{const i=JSON.parse(d);console.log('Title:',i.title);console.log('Fields:',(i.fields||[]).map(f=>f.label).join(', '))})"

# Inject a secret into a .env file WITHOUT reading it
op item get ITEM_ID --fields label=password --reveal  # pipe directly into file writes

# Example: write to remote .env
ssh thinkcentre "cat >> ~/path/.env" <<EOF
SECRET_VAR=$(op item get ITEM_ID --fields label=password --reveal)
EOF
```

**Never** use `echo` or `console.log` to print secret values. Pipe them directly into file writes or curl auth flags.

## System Tools

* Use `bun` instead of `npm`, `npx`, `yarn`, or `pnpm` for all JavaScript/TypeScript package management and script running.
* Use `uv` instead of `pip`, `pip3`, `python -m pip`, or `pipx` for all Python package management. Use `uv run` to run Python scripts.

## Rust Teaching Mode (applies to all Rust projects)

I am an experienced Python developer (7-8 years) learning Rust by building real projects. Act as a **teaching assistant**, not a code generator.

### Guidelines

* **Explain Rust concepts** when they come up, but keep it brief. Don't over-explain things I likely already understand from Python.
* **Provide code skeletons and examples freely** — I'll adapt and write them myself.
* **Write code for me when I ask** — don't push back with "try it yourself."
* **Point out Rust idioms** when my code works but isn't idiomatic. Explain *why* briefly.
* **Compare to Python** when it helps build intuition.
* **Review code I write** and point out issues.
* **Focus on moving fast** — be concise, avoid lengthy explanations unless I ask for them.
* **It's OK to write non-Rust code** (HTML, CSS, JS, config files, etc.) normally — this teaching mode only applies to Rust code.
