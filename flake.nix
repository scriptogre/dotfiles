{
  description = "Chris's MacBook configuration";

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

  outputs = { self, nixpkgs, home-manager, nix-darwin, nix-homebrew, mac-app-util, ... }@inputs: {
    darwinConfigurations."macbook" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        # System configuration
        {
          nixpkgs.config.allowUnfree = true;
          nix.enable = false;
          system.stateVersion = 6;

          networking.hostName = "macbook";

          system.primaryUser = "chris";

          users.users.chris.home = "/Users/chris";

          services.tailscale.enable = true;
        }

        # Homebrew
        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            enable = true;
            enableRosetta = true;
            user = "chris";
          };
          homebrew = {
            enable = true;
            onActivation = {
                autoUpdate = true;
                cleanup = "zap";
                upgrade = true;
            };
            casks = [
              "1password"
              "alfred"
              "alt-tab"
              "anydesk"
              "betterdisplay"
              "bettertouchtool"
              "brave-browser"
              "chatgpt"
              "claude"
              "discord"
              "firefox"
              "google-chrome"
              "itunes-volume-control"
              "jetbrains-toolbox"
              "karabiner-elements"
              "jordanbaird-ice"
              "ledger-live"
              "lm-studio"
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
              "vibetunnel"
            ];
          };
        }

        # Home Manager
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.chris = { pkgs, ... }: {
            home.username = "chris";
            home.homeDirectory = "/Users/chris";
            home.stateVersion = "25.05";

            # Shared zsh configuration
            programs.zsh = {
              enable = true;
              enableCompletion = true;
              autosuggestion.enable = true;
              syntaxHighlighting.enable = true;
              initContent = builtins.readFile ./dotfiles/shell/zshrc;
            };

            programs.direnv = {
              enable = true;
              nix-direnv.enable = true;
            };

            # Shared dotfiles
            home.file.".gitconfig".source = ./dotfiles/git/config;
            home.file.".config/git/ignore".source = ./dotfiles/git/ignore;

            home.packages = with pkgs; [
              # Development tools
              caddy
              gh
              git
              just
              uv
              nodejs_24
              mise
              gemini-cli
              claude-code

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

              # Extra packages
              iterm2
              nerd-fonts.jetbrains-mono
            ];
          };
        }

        mac-app-util.darwinModules.default
      ];
    };
  };
}