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
          #
          # Checks every hour whether an update is needed (last success > 20h ago).
          # This replaces a fixed 3 AM schedule so updates still happen if the
          # machine was asleep overnight. Retries flake downloads on network failure.
          launchd.user.agents.daily-update = {
            serviceConfig = {
              StartInterval = 3600;  # Check every hour
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
              stampFile = "${home}/.local/state/nix-daily-update-last-success";
            in ''
              # Fork the update into a background process so it survives the
              # launchd agent being reloaded by darwin-rebuild during activation.
              {
                # Raise file descriptor limit (macOS launchd default of 256 is too low for nix)
                ulimit -n 65536

                # Add git and other tools to path
                export PATH="/etc/profiles/per-user/${config.system.primaryUser}/bin:$PATH"

                # Skip if last successful update was less than 20 hours ago
                if [ -f "${stampFile}" ]; then
                  last_success=$(cat "${stampFile}")
                  now=$(date +%s)
                  hours_since=$(( (now - last_success) / 3600 ))
                  if [ "$hours_since" -lt 20 ]; then
                    exit 0
                  fi
                fi

                # Trim log to last 500 lines to prevent unbounded growth
                if [ -f "${logFile}" ]; then
                  tail -500 "${logFile}" > "${logFile}.tmp" && mv "${logFile}.tmp" "${logFile}"
                fi

                echo "Starting daily update at $(date)" >> ${logFile}
                cd ${repoPath}

                # Update flake inputs with retries (network can be flaky)
                max_retries=3
                flake_ok=false
                for attempt in $(seq 1 $max_retries); do
                  echo "Flake update attempt $attempt/$max_retries at $(date)" >> ${logFile}
                  if ${nix} flake update --flake ./hosts/${host} >> ${logFile} 2>&1; then
                    flake_ok=true
                    break
                  fi
                  if [ "$attempt" -lt "$max_retries" ]; then
                    echo "Retrying in $((attempt * 60))s..." >> ${logFile}
                    sleep $((attempt * 60))
                  fi
                done

                if [ "$flake_ok" = false ]; then
                  echo "Flake update failed after $max_retries attempts at $(date)" >> ${logFile}
                  /usr/bin/osascript -e 'display notification "Flake update failed after retries. Check ${logFile}" with title "Daily Update" subtitle "Failure"'
                  exit 1
                fi

                # Only quit apps during nighttime (11 PM - 6 AM)
                hour=$(date +%-H)
                if [ "$hour" -ge 23 ] || [ "$hour" -lt 6 ]; then
                  RUNNING_APPS=("Brave Browser" "Google Chrome" "Firefox" "Discord" "Spotify" "Obsidian" "Telegram")
                  for app in "''${RUNNING_APPS[@]}"; do
                    if pgrep -x "$app" > /dev/null; then
                      echo "Quitting $app for updates..." >> ${logFile}
                      osascript -e "quit app \"$app\"" 2>> ${logFile} || true
                    fi
                  done
                  sleep 5
                fi

                if sudo ${darwin-rebuild} switch --flake ./hosts/${host}#${host} >> ${logFile} 2>&1; then
                  # brew bundle (run by nix-darwin) installs missing casks but
                  # does not upgrade existing ones. Run brew upgrade explicitly.
                  echo "Upgrading Homebrew casks..." >> ${logFile}
                  ${brew} upgrade --greedy >> ${logFile} 2>&1 || true

                  echo "Update successful at $(date)" >> ${logFile}
                  mkdir -p "$(dirname "${stampFile}")"
                  date +%s > "${stampFile}"
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
              "ghostty"
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
          home-manager.users.chris = { pkgs, lib, ... }: {
            imports = [ ../../common/home.nix ];

            home.username = "chris";
            home.homeDirectory = "/Users/chris";

            # cd <project> from anywhere
            programs.zsh.initContent = lib.mkAfter ''
              export CDPATH=".:$HOME/Projects"
            '';

            # Karabiner config for key remaps (note: overwrites remaps created in the UI)
            home.file.".config/karabiner/karabiner.json" = {
                source = ./../../common/karabiner/karabiner.json;
                force = true;
            };

            # Ghostty terminal config
            home.file.".config/ghostty/config" = {
                source = ./../../common/ghostty/config;
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
