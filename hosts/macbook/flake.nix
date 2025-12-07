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

        # Automation & Security
        ({ config, pkgs, ...}: {
          # Enable Touch ID for sudo
          security.pam.services.sudo_local.touchIdAuth = true;

          # Allow passwordless sudo for darwin-rebuild (for auto-updates)
          security.sudo.extraConfig = ''
            chris ALL=(ALL:ALL) NOPASSWD: /run/current-system/sw/bin/darwin-rebuild
          '';

          # Daily Auto-Update
          launchd.user.agents.daily-update = {
            serviceConfig.StartCalendarInterval = [ { Hour = 3; Minute = 0; } ];

            script = let
              host = config.networking.hostName;
              home = config.users.users.${config.system.primaryUser}.home;
              repoPath = "${home}/Projects/dotfiles";
              nix = "/nix/var/nix/profiles/default/bin/nix";
              darwin-rebuild = "/run/current-system/sw/bin/darwin-rebuild";
              logFile = "${home}/Library/Logs/nix-daily-update.log";
            in ''
              # Add git and other tools to path
              export PATH="/etc/profiles/per-user/${config.system.primaryUser}/bin:$PATH"
              
              echo "Starting daily update at $(date)" >> ${logFile}
              cd ${repoPath}
              
              if ${nix} flake update --flake ./hosts/${host} >> ${logFile} 2>&1; then
                if sudo ${darwin-rebuild} switch --flake ./hosts/${host}#${host} >> ${logFile} 2>&1; then
                  echo "Update successful at $(date)" >> ${logFile}
                  /usr/bin/osascript -e 'display notification "System updated successfully" with title "Daily Update"'
                else
                  echo "Rebuild failed at $(date)" >> ${logFile}
                  /usr/bin/osascript -e 'display notification "Darwin rebuild failed. Check ${logFile}" with title "Daily Update" subtitle "Failure"'
                fi
              else
                echo "Flake update failed at $(date)" >> ${logFile}
                /usr/bin/osascript -e 'display notification "Flake update failed. Check ${logFile}" with title "Daily Update" subtitle "Failure"'
              fi
            '';
          };
        })

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
              "iterm2"
              "jetbrains-toolbox"
              "karabiner-elements"
              "jordanbaird-ice"
              "ledger-wallet"
              "lm-studio"
              "mos"
              "notunes"
              "nordvpn"
              "obs"
              "obsidian"
              "omnidisksweeper"
              "orbstack"
              "parallels"
              "proton-mail"
              "pycharm"
              "raycast"
              "spotify"
              "synology-drive"
              "telegram"
              "todoist-app"
              "vibetunnel"
              "volume-control"
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
            imports = [ ../../common/home.nix ];

            home.username = "chris";
            home.homeDirectory = "/Users/chris";

            # Karabiner config for key remaps (note: overwrites remaps created in the UI)
            home.file.".config/karabiner/karabiner.json" = {
                source = ./../../common/karabiner/karabiner.json;
                force = true;
            };
          };
}

        mac-app-util.darwinModules.default
      ];
    };
  };
}
