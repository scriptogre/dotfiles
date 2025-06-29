{
  description = "Chris's macOS configuration with nix-darwin + home-manager";

  # ============================================================================
  # INPUTS - External flake dependencies
  # ============================================================================
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

  # ============================================================================
  # OUTPUTS - System configurations
  # ============================================================================
  outputs = { nixpkgs, home-manager, nix-darwin, nix-homebrew, mac-app-util, ... }: 
  let
    # Configuration constants - modify these to customize your setup
    system = "aarch64-darwin";
    username = "chris";
    hostname = "macbook";
  in
  {
    darwinConfigurations.${hostname} = nix-darwin.lib.darwinSystem {
      inherit system;
      
      modules = [
        # ======================================================================
        # SYSTEM CONFIGURATION - macOS settings, services, and security
        # ======================================================================
        {
          # Basic system settings
          nixpkgs.config.allowUnfree = true;
          nixpkgs.config.allowBroken = true;
          nix.settings.experimental-features = [ "nix-command" "flakes" ];
          
          # System identity
          networking.hostName = hostname;
          system.stateVersion = 6;
          system.primaryUser = username;
          
          # Security settings
          security.pam.services.sudo_local.touchIdAuth = true;
          
          # System services
          services.tailscale.enable = true;
          
          # User account setup
          users.users.${username}.home = "/Users/${username}";
        }

        # ======================================================================
        # HOMEBREW CONFIGURATION - Add/remove casks here
        # ======================================================================
        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            enable = true;
            enableRosetta = true;
            user = username;
          };
          
          homebrew = {
            enable = true;
            onActivation.cleanup = "zap";
            
            # GUI Applications - add new apps here
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

        # ======================================================================
        # HOME MANAGER CONFIGURATION - User packages and dotfiles
        # ======================================================================
        home-manager.darwinModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            
            users.${username} = { pkgs, config, ... }: {
              # User identity
              home.username = username;
              home.homeDirectory = "/Users/${username}";
              home.stateVersion = "25.05";
              
              # Command-line tools and utilities - add new packages here
              home.packages = with pkgs; [
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
                fzf
                nano
                tailscale
                zoxide
                
                # Applications
                iterm2
                
                # Fonts
                nerd-fonts.jetbrains-mono
              ];
              
              # Git configuration - modify these settings as needed
              programs.git = {
                enable = true;
                userName = "scriptogre";
                userEmail = "git@christiantanul.com";
                extraConfig = {
                  core.excludesfile = "${config.home.homeDirectory}/.config/git/ignore";
                  init.defaultBranch = "master";
                  pull.rebase = true;
                };
              };
              
              # Git ignore file
              home.file.".config/git/ignore".source = ./gitignore;
            };
          };
        }

        # ======================================================================
        # MAC APP UTIL - macOS app integration
        # ======================================================================
        mac-app-util.darwinModules.default
      ];
    };
  };
}