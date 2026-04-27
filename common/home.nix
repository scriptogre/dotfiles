{ config, pkgs, lib, ... }:
let
  dotfiles = "${config.home.homeDirectory}/Projects/dotfiles";
in {
  home.stateVersion = "25.05";

  # Ensure ~/.local/bin is in PATH (for official Claude Code installer, etc.)
  home.sessionPath = [ "$HOME/.local/bin" ];

  # Disable nix management in home-manager (Determinate Nix manages this)
  nix.enable = lib.mkForce false;

  # Shared zsh configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
    };
    initContent = "source ${dotfiles}/common/shell/zshrc";
    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];
  };

  services.syncthing.enable = true;

  # Shared dotfiles
  home.file.".gitconfig".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/common/git/config";
  home.file.".config/git/ignore".source = ./git/ignore;
  home.file.".p10k.zsh".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/common/shell/p10k.zsh";

  # SSH host definitions (included from ~/.ssh/config via "Include config.d/*")
  # ~/.ssh/config itself is left unmanaged so 1Password and OrbStack can edit it.
  # Generated from common/network/aliases.nix — single source of truth.
  home.file.".ssh/config.d/hosts".text =
    let
      aliases = import ./network/aliases.nix;
      mkBlock = name: cfg:
        if cfg ? ssh then ''
          Host ${name}
            HostName ${cfg.ip}
            User ${cfg.ssh.user}
            ForwardAgent yes
        '' else "";
    in
      lib.concatStrings (lib.mapAttrsToList mkBlock aliases.hosts);

  # Shared packages
  home.packages = with pkgs; [
    # Development tools
    caddy
    gh
    git
    just
    uv
    gemini-cli
    opencode
    codex
    deno
    bun
    nodejs
    rustup

    # Secrets management
    _1password-cli
    age
    zstd

    # System utilities
    iperf3
    fzf
    curl
    htop
    nano
    tailscale
    wget
    bat      # alternative to `cat`
    ripgrep  # alternative to `grep`
    eza      # alternative to `ls`
    micro    # alternative to `nano`
    imagemagick
    ffmpeg
    oxipng
    pngquant

    # Extra packages
    nerd-fonts.jetbrains-mono
  ];
}