{ pkgs, system, inputs, username, ... }:

{
  # System-wide Nixpkgs configuration
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowBroken = true;

  # Nix settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Define the primary user for system-wide configurations like Homebrew
  system.primaryUser = username;

  # Homebrew integration for casks (GUI applications)
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";

    casks = [
      "1password"
      "1password-cli" # CLI can also be a Nix package
      "alfred"
      "alt-tab"
      "anydesk"
      "betterdisplay"
      "bettertouchtool"
      "brave-browser"
      "chatgpt"
      "discord"
      "itunes-volume-control"
      "karabiner-elements"
      "ledger-live"
      "mos"
      "notunes"
      "obs"
      "obsidian"
      "omnidisksweeper"
      "orbstack"
      "parallels"
      "proton-mail"
      "pycharm" # Consider JetBrains Toolbox App cask for managing IDEs
      "slack"
      "spotify"
      "synology-drive"
      "telegram"
      "zoom"
    ];
  };

  # Example: Setting system hostname
  networking.hostName = "macbook";

  # Enable Tailscale service system-wide if desired
  services.tailscale.enable = true;

  # Security settings
  security.pam.services.sudo_local.touchIdAuth = true;

  # System-wide state version for nix-darwin
  system.stateVersion = 6;
}