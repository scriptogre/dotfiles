# Dotfiles

Nix-based declarative homelab configuration. Each machine has its own host directory — read its `flake.nix` to understand the setup.

## Structure

- `hosts/<hostname>/` — Per-host configuration (flake.nix, services, modules)
- `common/` — Shared config (shell, git, ssh) imported by all hosts
- `Justfile` — Available commands (rebuild, deploy, etc.)

## Principles

- **Everything must be declarative.** All configuration is tracked in this repo and applied via
  `nixos-rebuild` / `darwin-rebuild`. Never make imperative changes that a rebuild would overwrite.
  If you need to change something, change it in the Nix config and rebuild.
- **No manual state.** Service configs, firewall rules, system packages, user settings — all in flake.nix
  or its imported modules. If it's not in the repo, it shouldn't exist on the machine.

## System Tools

- Use `bun` instead of `npm`/`npx`/`yarn`/`pnpm`
- Use `uv` instead of `pip`/`pip3`/`pipx`, `uv run` to run Python scripts
