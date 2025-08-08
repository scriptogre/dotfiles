# Common configuration that can be optionally imported by host configurations
{ pkgs }:

{
  # Common packages for all systems that import this module
  packages = with pkgs; [
    # Development tools
    caddy
    gh
    git
    just
    uv
    nodejs_24
    mise

    # Secrets management
    _1password-cli
    
    # System utilities
    curl
    htop
    nano
    tailscale
    wget
    
    # Shell
    oh-my-zsh
    zsh
    
    # Docker tools
    docker-compose
    lazydocker
  ];

  # Home Manager configuration
  homeManagerConfig = {
    home.stateVersion = "25.05";
    
    # Shared zsh configuration
    programs.zsh = {
      enable = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      initContent = builtins.readFile ../dotfiles/shell/zshrc;
    };
    
    # Shared dotfiles
    home.file.".gitconfig".source = ../dotfiles/git/config;
    home.file.".config/git/ignore".source = ../dotfiles/git/ignore;
  };

  # Helper function to merge common config with host-specific extras
  mkHomeConfig = { extraPackages ? [], extraConfig ? {} }: 
    let
      common = (import ./common.nix { inherit pkgs; });
    in
    common.homeManagerConfig // {
      home.packages = common.packages ++ extraPackages;
    } // extraConfig;
}