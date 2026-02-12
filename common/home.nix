{ pkgs, lib, ... }: {
  home.stateVersion = "25.05";

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
    initContent = builtins.readFile ./shell/zshrc;
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
  home.file.".gitconfig".source = ./git/config;
  home.file.".config/git/ignore".source = ./git/ignore;
  home.file.".p10k.zsh".source = ./shell/p10k.zsh;

  # SSH host definitions (included from ~/.ssh/config via "Include config.d/*")
  # ~/.ssh/config itself is left unmanaged so 1Password and OrbStack can edit it.
  home.file.".ssh/config.d/hosts".source = ./ssh/hosts;

  # Shared packages
  home.packages = with pkgs; [
    # Development tools
    caddy
    gh
    git
    just
    uv
    gemini-cli
    claude-code
    nodejs_20
    deno
    bun
    pnpm
    rustup

    # Secrets management
    _1password-cli
    age

    # System utilities
    socat  # UDP forwarding for Moonlight
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