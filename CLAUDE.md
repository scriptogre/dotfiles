# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Important: Applying Changes

All files in this repo are managed by Nix/home-manager. **Editing files here does NOT immediately apply changes.**

After any edit, run:
```bash
cd ~/Projects/dotfiles && just rebuild
```

This rebuilds the Nix configuration and symlinks files (like `~/.zshrc`) to the Nix store.

## Common Commands

- `just rebuild` - Applies configuration changes (runs `darwin-rebuild switch`)
- `just update` - Updates Nix flakes to latest versions
- `nix flake check` - Validates flake configuration

## Architecture

This is a Nix-based macOS configuration using nix-darwin and Home Manager. The setup is declarative and reproducible.

**Key Files:**
- `flake.nix` - Main configuration entry point defining system, user packages, and Homebrew apps
- `Justfile` - Task runner with common operations
- `gitignore` - Global git ignore file referenced in Home Manager config

**Configuration Structure:**
- System configuration (hostname: "macbook", user: "chris", aarch64-darwin)
- Homebrew integration for GUI applications via nix-homebrew
- Home Manager for user-level packages and dotfiles
- Security settings include TouchID for sudo

**Package Management:**
- Nix packages defined in `home.packages` array (flake.nix:129-153)
- GUI applications managed via Homebrew casks (flake.nix:79-109)
- Git configuration managed declaratively (flake.nix:156-165)

**Customization Points:**
- Add new CLI tools to `home.packages` array
- Add new GUI apps to `homebrew.casks` array
- Modify user constants at top of flake.nix (system, username, hostname)