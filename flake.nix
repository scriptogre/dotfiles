{
  description = "Chris's homelab - environment configuration for all machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    mac-app-util.url = "github:hraban/mac-app-util";
  };

  outputs = { self, nixpkgs, home-manager, nix-darwin, nix-homebrew, mac-app-util }:
    let
      # Common packages for all systems
      commonPackages = pkgs: with pkgs; [
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

      # Home configuration shared across all systems
      homeConfig = { pkgs, extraPackages ? [] }: {
        home.stateVersion = "25.05";
        
        # Packages: common + extra per machine
        home.packages = (commonPackages pkgs) ++ extraPackages;
        
        # Shared zsh configuration
        programs.zsh = {
          enable = true;
          enableCompletion = true;
          autosuggestion.enable = true;
          syntaxHighlighting.enable = true;
          initContent = builtins.readFile ./dotfiles/shell/zshrc;
        };
        
        # Shared dotfiles
        home.file.".gitconfig".source = ./dotfiles/git/config;
        home.file.".config/git/ignore".source = ./dotfiles/git/ignore;
      };

      # Shared inputs for host configurations
      sharedArgs = {
        inherit nixpkgs home-manager nix-darwin nix-homebrew mac-app-util;
        inherit commonPackages homeConfig;
      };
    in
    {
      # macOS System Configurations
      darwinConfigurations = {
        macbook = import ./hosts/macbook.nix sharedArgs;
      };

      # NixOS System Configurations  
      nixosConfigurations = {
        acasa = import ./hosts/acasa.nix sharedArgs;
        # betania is now a standalone flake in hosts/betania.nix
      };

      # Home Manager Configurations
      homeConfigurations = {
        # macOS
        "chris@macbook" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          modules = [(
            {
              home.username = "chris";
              home.homeDirectory = "/Users/chris";
              home.stateVersion = "25.05";
            } // homeConfig {
              pkgs = nixpkgs.legacyPackages.aarch64-darwin;
              extraPackages = with nixpkgs.legacyPackages.aarch64-darwin; [
                iterm2
                nerd-fonts.jetbrains-mono
              ];
            }
          )];
        };
      };
    };
}