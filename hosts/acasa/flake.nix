{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs, ... }: {
    nixosConfigurations.acasa = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        ({ pkgs, ... }: {
          nix.settings.experimental-features = [ "nix-command" "flakes" ];

          # Networking
          networking.hostName = "acasa";
          networking.networkmanager.enable = true;
          networking.firewall.enable = true;
          networking.firewall.allowedTCPPorts = [ 53 ];
          networking.firewall.allowedUDPPorts = [ 53 ];

          # Time zone
          time.timeZone = "Europe/Bucharest";

          # Desktop Environment
          services.displayManager.gdm.enable = true;
          services.desktopManager.gnome.enable = true;
          services.xserver.enable = true;
          services.xserver.xkb = {
            layout = "us";
            variant = "";
          };

          # Enable audio
          services.pulseaudio.enable = false;
          security.rtkit.enable = true;
          services.pipewire = {
            enable = true;
            alsa.enable = true;
            alsa.support32Bit = true;
            pulse.enable = true;
          };

          # Create user
          users.users.admin = {
            isNormalUser = true;
            hashedPassword = "$6$7Jc0AeOXfY6ZcPrq$SEh.YssqY6SJaiJXTAox/eEZX80iPjIb0UxcAn7kvJUFhOgjjmUZvWG4CbcLr3GhUq.Jj6BSIfcsj8fnADcW8.";  # cy9 aia
            extraGroups = [ "wheel" "networkmanager" ];
          };
          security.sudo.wheelNeedsPassword = false; # Disable password for wheel group

          # Optimize for 24/7 running
          systemd.targets.sleep.enable = false;
          systemd.targets.suspend.enable = false;
          systemd.targets.hibernate.enable = false;
          systemd.targets.hybrid-sleep.enable = false;
          systemd.targets.suspend-then-hibernate.enable = false;

          # Monitor CPU temperature
          services.thermald.enable = true;

          # Enable Home Assistant
          services.home-assistant = {
            enable = true;
            openFirewall = true;
            config = {
              default_config = {};
            };
          };

          # Enable AdGuard Home
          services.adguardhome = {
            enable = true;
            openFirewall = true;
            mutableSettings = false;
            settings = {
              dns = {
                bind_hosts = [ "0.0.0.0" ];
                bootstrap_dns = [ "192.168.0.1" ];  # Get from router
              };
              filtering = {
                rewrites = [
                  {
                    domain = "home-assistant";
                    answer = "192.168.1.144";
                  }
                  {
                    domain = "adguard";
                    answer = "192.168.1.144";
                  }
                ];
              };
            };
          };


          # Enable Caddy
          services.caddy = {
            enable = true;
            virtualHosts."home-assistant".extraConfig = ''
              reverse_proxy localhost:8123
              tls internal
            '';
            virtualHosts."adguard".extraConfig = ''
              reverse_proxy localhost:3000
              tls internal
            '';
          };


          # Enable Tailscale
          services.tailscale = {
            enable = true;
            useRoutingFeatures = "both";
          };
          # Apply optimizations (https://tailscale.com/kb/1320/performance-best-practices#linux-optimizations-for-subnet-routers-and-exit-nodes)
          systemd.services.tailscale-ethtool-optimize = {
            description = "Apply ethtool optimizations for Tailscale subnet router/exit node";
            serviceConfig = {
              Type = "oneshot";
              User = "root";
              ExecStart = ''
                NETDEV=$(${pkgs.iproute2}/bin/ip -o route get 8.8.8.8 | ${pkgs.coreutils}/bin/cut -f 5 -d " ")
                ${pkgs.ethtool}/bin/ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
              '';
            };
            wantedBy = [ "network-pre.target" ];
            after = [ "network-pre.target" ];
          };
          # Start Tailscale automatically
          systemd.services.tailscale-up = {
            description = "Tailscale Up";
            after = [ "network-online.target" "tailscale.service" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = "yes";
              ExecStart = "${nixpkgs.lib.getBin pkgs.tailscale}/bin/tailscale up --accept-dns=false --advertise-routes=192.168.1.0/24 --ssh";
            };
          };


          # Install packages
          environment.systemPackages = with pkgs; [
            git
            gemini-cli
            just
            dnsutils
            ethtool
            iproute2
            coreutils
          ];


          # Boot configuration
          boot.loader = {
            systemd-boot.enable      = true;
            efi.canTouchEfiVariables = true;
          };


          # State Version
          system.stateVersion = "24.11";
        })
      ];
    };
  };
}