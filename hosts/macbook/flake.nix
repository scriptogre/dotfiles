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
            serviceConfig = {
              StartCalendarInterval = [ { Hour = 3; Minute = 0; } ];
              # Don't kill child processes when the agent is reloaded.
              # darwin-rebuild reloads this agent during activation, which
              # would otherwise kill the running update script.
              AbandonProcessGroup = true;
            };

            script = let
              host = config.networking.hostName;
              home = config.users.users.${config.system.primaryUser}.home;
              repoPath = "${home}/Projects/dotfiles";
              nix = "/nix/var/nix/profiles/default/bin/nix";
              darwin-rebuild = "/run/current-system/sw/bin/darwin-rebuild";
              logFile = "${home}/Library/Logs/nix-daily-update.log";
              brew = "/opt/homebrew/bin/brew";
            in ''
              # Fork the update into a background process so it survives the
              # launchd agent being reloaded by darwin-rebuild during activation.
              {
                # Raise file descriptor limit (macOS launchd default of 256 is too low for nix)
                ulimit -n 65536

                # Add git and other tools to path
                export PATH="/etc/profiles/per-user/${config.system.primaryUser}/bin:$PATH"

                echo "Starting daily update at $(date)" >> ${logFile}
                cd ${repoPath}

                # Update flake inputs first (before quitting any apps)
                if ! ${nix} flake update --flake ./hosts/${host} >> ${logFile} 2>&1; then
                  echo "Flake update failed at $(date)" >> ${logFile}
                  /usr/bin/osascript -e 'display notification "Flake update failed. Check ${logFile}" with title "Daily Update" subtitle "Failure"'
                  exit 1
                fi

                # Only quit apps after flake update succeeds
                RUNNING_APPS=("Brave Browser" "Google Chrome" "Firefox" "Discord" "Spotify" "Obsidian" "Telegram")
                for app in "''${RUNNING_APPS[@]}"; do
                  if pgrep -x "$app" > /dev/null; then
                    echo "Quitting $app for updates..." >> ${logFile}
                    osascript -e "quit app \"$app\"" 2>> ${logFile} || true
                  fi
                done
                sleep 5

                if sudo ${darwin-rebuild} switch --flake ./hosts/${host}#${host} >> ${logFile} 2>&1; then
                  echo "Update successful at $(date)" >> ${logFile}
                  /usr/bin/osascript -e 'display notification "System updated successfully" with title "Daily Update"'
                else
                  echo "Rebuild failed at $(date)" >> ${logFile}
                  /usr/bin/osascript -e 'display notification "Darwin rebuild failed. Check ${logFile}" with title "Daily Update" subtitle "Failure"'
                fi
              } &
            '';
          };
        })

        # Strip quarantine flags from Nix-managed apps so macOS doesn't
        # flag them as "from an unidentified developer" after updates
        {
          system.activationScripts.postActivation.text = ''
            echo "Stripping quarantine flags from Nix apps..."
            /usr/bin/xattr -dr com.apple.quarantine /Applications/Nix\ Apps/*.app 2>/dev/null || true
          '';
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
            greedyCasks = true;
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
              "codex"
              "claude-code"
              "firefox"
              "google-chrome"
              "iterm2"
              "jetbrains-toolbox"
              "karabiner-elements"
              "jordanbaird-ice"
              "mos"
              "notunes"
              "nordvpn"
              "obs"
              "obsidian"
              "omnidisksweeper"
              "orbstack"
              "parallels@20"
              "proton-mail"
              "pycharm"
              "raycast"
              "spotify"
              "synology-drive"
              "telegram"
              "todoist-app"
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

            # Synology Drive global blacklist (excludes dev artifacts from sync/backup)
            home.file."Library/Application Support/SynologyDrive/data/blacklist.filter" = {
                source = ./../../common/synology-drive/blacklist.filter;
                force = true;
            };
          };
}

        mac-app-util.darwinModules.default
      ];
    };
  };
}
