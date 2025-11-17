{ pkgs, ... }: {
  home.stateVersion = "25.05";

  # Shared zsh configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    initContent = builtins.readFile ./shell/zshrc;
  };

  # Shared dotfiles
  home.file.".gitconfig".source = ./git/config;
  home.file.".config/git/ignore".source = ./git/ignore;

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

    # System utilities
    curl
    htop
    nano
    tailscale
    wget
    bat      # alternative to `cat`
    ripgrep  # alternative to `grep`
    eza      # alternative to `ls`
    rip2     # alternative to `rm`
    fd       # alternative to `find`
    micro    # alternative to `nano`
    imagemagick
    ffmpeg
    oxipng
    pngquant

    # Shell
    oh-my-zsh

    # Extra packages
    nerd-fonts.jetbrains-mono
  ];
}