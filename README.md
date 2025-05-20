# dotfiles

Personal configuration files using Nix and NixOS Home Manager.

## Overview

This repository contains my personal configuration files and system setup using Nix and NixOS Home Manager. It includes both general Nix configurations and Darwin-specific settings.

## Setup

### Prerequisites

- Nix
- Nix Flakes

### Installation

1. Clone this repository:
```bash
git clone https://github.com/scriptogre/dotfiles.git ~/.dotfiles
```

2. Run the setup:
```bash
just update && just switch
```

## Configuration Files

- `flake.nix`: Main flake configuration
- `darwin-configuration.nix`: Darwin-specific system configuration
- `home.nix`: Home Manager configuration
- `Justfile`: Just tasks for common operations

## License

MIT