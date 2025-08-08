{
  description = "Betania's NixOS Configuration - Standalone flake for Windows Server VM";
 
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
 
  outputs = { self, nixpkgs, home-manager, ... }:
    let
      # Common packages for all systems
      commonPackages = pkgs: with pkgs; [
        # Development tools
        caddy
        gh
        git
        just
        uv
        
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
        
        # Shared zsh configuration would go here if needed
        programs.zsh = {
          enable = true;
          enableCompletion = true;
          autosuggestion.enable = true;
          syntaxHighlighting.enable = true;
        };
      };
    in
    {
      nixosConfigurations.betania = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          # Hardware configuration will need to be copied from VM
          # ./hardware-configuration.nix
          
          # Minimal hardware configuration for build testing
          ({ pkgs, ... }: {
            # Basic filesystem configuration (placeholder)
            fileSystems."/" = {
              device = "/dev/sda1";
              fsType = "ext4";
            };

            # === BOOTLOADER ===
            boot.loader.grub.enable = true;
            boot.loader.grub.device = "/dev/sda";
            boot.loader.grub.useOSProber = true;

            # === NETWORKING ===
            networking.hostName = "betania";
            networking.networkmanager.enable = true;
            networking.firewall = {
              enable = true;
              trustedInterfaces = [ "tailscale0" ];
              allowedTCPPorts = [ 
                3389  # RDP
                80    # HTTP (for future Caddy setup)
                443   # HTTPS (for future Caddy setup)
              ];
            };

            # === DESKTOP ENVIRONMENT ===
            services.xserver.enable = true;
            services.displayManager.gdm.enable = true;
            services.desktopManager.gnome.enable = true;

            # === GNOME REMOTE DESKTOP (replaces Sunshine) ===
            services.gnome.gnome-remote-desktop.enable = true;
            services.xrdp = {
              enable = true;
              defaultWindowManager = "${pkgs.gnome-session}/bin/gnome-session";
              openFirewall = true;
            };

            # === DISABLE AUTO-LOGIN (prevents RDP black screen) ===
            services.displayManager.autoLogin.enable = false;
            # Disable getty services that interfere with remote desktop
            systemd.services."getty@tty1".enable = false;
            systemd.services."autovt@tty1".enable = false;

            # === TAILSCALE WITH AUTO-CONNECT ===
            services.tailscale = {
              enable = true;
              openFirewall = true;
              useRoutingFeatures = "client";
            };
            
            # Auto-connect to Tailscale on startup
            # Set TAILSCALE_AUTH_KEY environment variable or create /etc/tailscale-auth-key file
            systemd.services.tailscale-up = {
              description = "Tailscale Up";
              after = [ "network-online.target" "tailscale.service" ];
              wants = [ "network-online.target" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = "yes";
                ExecStart = pkgs.writeShellScript "tailscale-up" ''
                  # Try auth key from environment variable first
                  if [ -n "$TAILSCALE_AUTH_KEY" ]; then
                    ${pkgs.lib.getBin pkgs.tailscale}/bin/tailscale up --auth-key="$TAILSCALE_AUTH_KEY" --ssh --accept-routes
                  # Try auth key from file
                  elif [ -f /etc/tailscale-auth-key ]; then
                    AUTH_KEY=$(cat /etc/tailscale-auth-key)
                    ${pkgs.lib.getBin pkgs.tailscale}/bin/tailscale up --auth-key="$AUTH_KEY" --ssh --accept-routes
                  # Fallback to manual auth (will require browser)
                  else
                    echo "No auth key found. Manual authentication required."
                    ${pkgs.lib.getBin pkgs.tailscale}/bin/tailscale up --ssh --accept-routes
                  fi
                '';
              };
              environment = {
                # You can set the auth key here directly (not recommended for security)
                # TAILSCALE_AUTH_KEY = "tskey-auth-...";
              };
            };

            # === AUDIO ===
            services.pulseaudio.enable = false;
            security.rtkit.enable = true;
            services.pipewire = {
              enable = true;
              alsa.enable = true;
              alsa.support32Bit = true;
              pulse.enable = true;
            };

            # === DOCKER SUPPORT ===
            virtualisation.docker = {
              enable = true;
              enableOnBoot = true;
            };

            # === USER ACCOUNT ===
            users.users.admin = {
              isNormalUser = true;
              extraGroups = [ "wheel" "networkmanager" "docker" ];
              password = "admin";  # TODO: Change to hashed password for security
            };

            # === SUDO CONFIGURATION ===
            security.sudo.wheelNeedsPassword = false;

            # === ALLOW UNFREE PACKAGES ===
            nixpkgs.config.allowUnfree = true;

            # === SYSTEM PACKAGES ===
            environment.systemPackages = (commonPackages pkgs) ++ (with pkgs; [
              # VM-specific packages
              brave
              kdePackages.kate
              nil
              
              # Development tools
              docker-compose
              
              # Remote desktop clients (for testing)
              remmina
              freerdp3
              
              # System monitoring
              neofetch
              
              # Network utilities
              dnsutils
            ]);

            # === NIX SETTINGS ===
            nix.settings = {
              experimental-features = [ "nix-command" "flakes" ];
              auto-optimise-store = true;
            };

            # === AUTOMATIC SYSTEM MAINTENANCE ===
            system.autoUpgrade = {
              enable = true;
              dates = "weekly";
              flags = [ "--update-input" "nixpkgs" ];
            };

            nix.gc = {
              automatic = true;
              dates = "weekly";
              options = "--delete-older-than 30d";
            };

            # === TIME ZONE ===
            time.timeZone = "Europe/Bucharest";

            # === SYSTEM VERSION ===
            system.stateVersion = "25.05";
          })
        ];
      };
    };
}