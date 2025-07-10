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

  outputs = { nixpkgs, home-manager, nix-darwin, nix-homebrew, mac-app-util, ... }: 
  let
    commonPackages = pkgs: with pkgs; [
      # Development tools
      caddy
      gh
      git
      just
      neovim
      ripgrep
      ruff
      sqlite
      terraform
      uv
      
      # System utilities
      curl
      fzf
      htop
      nano
      tailscale
      tmux
      tree
      wget
      zoxide
      
      # Shell
      oh-my-zsh
      zsh
      
      # Docker tools
      docker-compose
      lazydocker
    ];

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
        initExtra = builtins.readFile ./dotfiles/shell/zshrc;
      };
      
      # Shared dotfiles
      home.file.".gitconfig".source = ./dotfiles/git/config;
      home.file.".config/git/ignore".source = ./dotfiles/git/ignore;
    };
  in
  {
    # ========================================================================
    # macOS System Configuration
    # ========================================================================
    darwinConfigurations.macbook = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        # System configuration
        {
          nixpkgs.config.allowUnfree = true;
          nix.settings.experimental-features = [ "nix-command" "flakes" ];
          networking.hostName = "macbook";
          system.stateVersion = 6;
          services.tailscale.enable = true;
          users.users.chris.home = "/Users/chris";
        }

        # Homebrew
        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = { enable = true; enableRosetta = true; user = "chris"; };
          homebrew = {
            enable = true;
            onActivation.cleanup = "zap";
            casks = [
              "1password"
              "1password-cli"
              "alfred"
              "alt-tab"
              "anydesk"
              "betterdisplay"
              "bettertouchtool"
              "brave-browser"
              "chatgpt"
              "claude"
              "discord"
              "itunes-volume-control"
              "jetbrains-toolbox"
              "karabiner-elements"
              "jordanbaird-ice"
              "ledger-live"
              "mos"
              "notunes"
              "obs"
              "obsidian"
              "omnidisksweeper"
              "orbstack"
              "parallels"
              "proton-mail"
              "pycharm"
              "spotify"
              "synology-drive"
              "telegram"
              "todoist-app"
            ];
          };
        }

        # Home Manager
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.chris = { pkgs, ... }: (homeConfig {
            inherit pkgs;
            extraPackages = with pkgs; [
              iterm2
              nerd-fonts.jetbrains-mono
            ];
          }) // {
            home.username = "chris";
            home.homeDirectory = "/Users/chris";
          };
        }

        mac-app-util.darwinModules.default
      ];
    };

    # ========================================================================
    # Home Manager Configurations
    # ========================================================================
    homeConfigurations = {
      # macOS
      "chris@macbook" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-darwin;
        modules = [({
          home.username = "chris";
          home.homeDirectory = "/Users/chris";
        } // (homeConfig {
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          extraPackages = with nixpkgs.legacyPackages.aarch64-darwin; [
            iterm2
            nerd-fonts.jetbrains-mono
          ];
        }))];
      };

      # Synology VM
      "chris@vm" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        modules = [({
          home.username = "chris";
          home.homeDirectory = "/home/chris";
        } // (homeConfig {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        }))];
      };
      
      # Raspberry Pi 5
      "chris@pi" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.aarch64-linux;
        modules = [({
          home.username = "chris";
          home.homeDirectory = "/home/chris";
        } // (homeConfig {
          pkgs = nixpkgs.legacyPackages.aarch64-linux;
        }))];  
      };
    };
  };
}