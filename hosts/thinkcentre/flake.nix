{
  description = "ThinkCentre M90Q Gen 4 Configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }: {
    nixosConfigurations."thinkcentre" = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        # ./gaming-vm.nix  # Disabled — reclaim 41GB disk space
        # Home Manager
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "hm-backup";
          home-manager.users.chris = { pkgs, lib, ... }: {
            imports = [ ../../common/home.nix ];
            home.username = "chris";
            home.homeDirectory = "/home/chris";
            # Disable home-manager Syncthing — the system-level service handles
            # it with guiAddress=0.0.0.0:8384 (needed for Caddy reverse proxy).
            services.syncthing.enable = lib.mkForce false;
            dconf.settings = {
              "org/gnome/desktop/session" = {
                idle-delay = lib.hm.gvariant.mkUint32 0;
              };
              "org/gnome/desktop/screensaver" = {
                lock-enabled = false;
              };
            };

            # cd <service> from anywhere — resolves infra services then projects
            programs.zsh.initContent = lib.mkAfter ''
              export CDPATH=".:$HOME/Projects/dotfiles/hosts/thinkcentre:$HOME/Projects"
            '';
          };
        }

        # System configuration
        ({ pkgs, config, lib, ... }: {

            # Users
            users.users.chris = {
              isNormalUser = true;
              shell = pkgs.zsh;
              extraGroups = [ "wheel" "networkmanager" "docker" "video" "render" "input" "libvirtd" "kvm" ];
              password = "chris";
              openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINLGEYgN5pbs2u1eMfTnpKUqHCm8fPuC/vSeV4Ht0KyL" # home_network_key_2 (1Password)
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHjvbv2K5oydAynpFJIJKHlvbvex6HheCYIJq7Sm48ZT" # openclaw-container
              ];
            };
            programs.zsh.enable = true;
            security.sudo.wheelNeedsPassword = false;

            # Bootloader
            boot.loader.systemd-boot.enable = true;
            boot.loader.systemd-boot.consoleMode = "auto";
            boot.loader.efi.canTouchEfiVariables = true;

            # Networking
            networking.hostName = "thinkcentre";
            networking.networkmanager.enable = true;
            networking.wireless.enable = lib.mkForce false;
            networking.networkmanager.ensureProfiles.profiles = {
              "Wired Static" = {
                connection = {
                  id = "Wired Static";
                  type = "ethernet";
                  interface-name = "eno2";
                  autoconnect = "true";
                  autoconnect-priority = "100";
                };
                ipv4 = {
                  method = "manual";
                  address1 = "192.168.0.12/24,192.168.0.1";
                  dns = "192.168.0.1;";
                };
              };
            };
            networking.firewall = {
              enable = true;
              trustedInterfaces = [ "tailscale0" ];
              allowedTCPPorts = [
                80     # HTTP (Caddy)
                443    # HTTPS (Caddy)
                53     # DNS (AdGuard)
                853    # DNS-over-TLS (AdGuard)
                3000   # SpacetimeDB
                3389   # RDP
                5900   # VNC (Windows VM install)
                8123   # Home Assistant
                8384   # Syncthing GUI (behind Caddy lan-only)
                32400  # Plex
              ];
              allowedUDPPorts = [
                53     # DNS (AdGuard)
                443    # HTTP/3 (Caddy)
                8853   # DNS-over-QUIC (AdGuard)
              ];
            };

            # Intel GPU (QuickSync hardware transcoding + Vulkan for gaming)
            hardware.graphics = {
              enable = true;
              enable32Bit = true;    # 32-bit Vulkan/GL for Wine games
              extraPackages = with pkgs; [
                intel-media-driver    # VAAPI for 12th/13th gen+
                vpl-gpu-rt            # Intel Video Processing Library
                intel-compute-runtime # OpenCL support
                vulkan-loader        # Vulkan ICD loader
              ];
              extraPackages32 = with pkgs.pkgsi686Linux; [
                intel-media-driver    # 32-bit VAAPI
                vulkan-loader        # 32-bit Vulkan
              ];
            };

            # SMB credentials for Synology NAS (stored in /var/lib, which persists across rebuilds).
            #
            # If you ever need to update these (e.g. after changing your Synology password):
            #   1. On your Mac, run:  op read 'op://wntgzcyr5x3bxict6nnuroeigu/abpyarbqdajzkug7x3o7webp4y/password'
            #   2. SSH into thinkcentre:  ssh thinkcentre
            #   3. Write the credentials file:
            #        sudo bash -c 'printf "username=chris\npassword=YOUR_PASSWORD\n" > /var/lib/nas-credentials'
            #        sudo chmod 600 /var/lib/nas-credentials
            #   4. Remount:  sudo systemctl restart mnt-nas-media.automount
            #
            # TODO: automate via opnix once op CLI version mismatch is resolved.

            # SMB mounts for Synology
            fileSystems."/mnt/nas/media" = {
              device = "//192.168.0.14/media_server/media";
              fsType = "cifs";
              options = [
                "credentials=/var/lib/nas-credentials" "uid=1000" "gid=100"
                "nofail" "x-systemd.automount" "x-systemd.idle-timeout=60"
                "x-systemd.device-timeout=5s" "x-systemd.mount-timeout=5s"
              ];
            };
            fileSystems."/mnt/nas/media_server" = {
              device = "//192.168.0.14/media_server";
              fsType = "cifs";
              options = [
                "credentials=/var/lib/nas-credentials" "uid=1000" "gid=100"
                "nofail" "x-systemd.automount" "x-systemd.idle-timeout=60"
                "x-systemd.device-timeout=5s" "x-systemd.mount-timeout=5s"
              ];
            };
            fileSystems."/mnt/nas/homes" = {
              device = "//192.168.0.14/homes";
              fsType = "cifs";
              options = [
                "credentials=/var/lib/nas-credentials" "uid=1000" "gid=100"
                "nofail" "x-systemd.automount" "x-systemd.idle-timeout=60"
                "x-systemd.device-timeout=5s" "x-systemd.mount-timeout=5s"
              ];
            };

            # Nix garbage collection
            nix.gc = {
              automatic = true;
              dates = "weekly";
              options = "--delete-older-than 14d";
            };

            # Docker
            virtualisation.docker.enable = true;
            # Route container DNS through AdGuard so they resolve local domains
            # (e.g. gitea.christiantanul.com → 192.168.0.14) instead of going through Cloudflare
            virtualisation.docker.daemon.settings = {
              dns = [ "192.168.0.12" ];
            };

            # Desktop Environment (Wayland)
            services.xserver.enable = true;
            services.displayManager.gdm.enable = true;
            services.desktopManager.gnome.enable = true;

            # Keep machine awake and reachable (headless server)
            services.logind = {
              settings.Login = {
                HandleLidSwitch = "ignore";
                IdleAction = "ignore";
                HandleSuspendKey = "ignore";
                HandleHibernateKey = "ignore";
              };
            };
            systemd.targets.sleep.enable = false;
            systemd.targets.suspend.enable = false;
            systemd.targets.hibernate.enable = false;
            systemd.targets.hybrid-sleep.enable = false;

            # Auto-login (no session timeout)
            services.displayManager.autoLogin = {
              enable = true;
              user = "chris";
            };

            # Remote Desktop Protocol (RDP)
            services.gnome.gnome-remote-desktop.enable = true;
            services.xrdp = {
              enable = true;
              defaultWindowManager = "${pkgs.gnome-session}/bin/gnome-session";
            };

            # Cockpit: web-based system management UI (port 9090)
            # Provides a browser dashboard for monitoring, terminal access, and VM management.
            services.cockpit = {
              enable = true;
              port = 9090;
              openFirewall = true;
              settings = {
                WebService = {
                  AllowUnencrypted = true;
                  Origins = lib.mkForce "https://thinkcentre.christiantanul.com https://localhost:9090";
                };
              };
            };
            # libvirt-dbus bridge (required by Cockpit for VM management via cockpit-machines)
            users.groups.libvirtdbus = {};
            users.users.libvirtdbus = {
              isSystemUser = true;
              group = "libvirtdbus";
              extraGroups = [ "libvirtd" ];
            };
            systemd.services.libvirt-dbus = {
              description = "Libvirt DBus Service (system)";
              after = [ "libvirtd.service" ];
              requires = [ "libvirtd.service" ];
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                Type = "dbus";
                BusName = "org.libvirt";
                User = "libvirtdbus";
                ExecStart = "${pkgs.libvirt-dbus}/sbin/libvirt-dbus --system";
              };
            };

            # SSH
            services.openssh = {
              enable = true;
              settings = {
                PasswordAuthentication = false;
                PermitRootLogin = "no";
              };
            };

            # Syncthing (bidirectional sync of ~/Projects with Mac)
            # See hosts/thinkcentre/SYNCTHING.md for details and gotchas.
            services.syncthing = {
              enable = true;
              user = "chris";
              group = "users";
              dataDir = "/home/chris";
              configDir = "/home/chris/.config/syncthing";
              guiAddress = "0.0.0.0:8384";
              settings = {
                devices.macbook = {
                  id = "HGJIECR-C6TTOJ2-N3XEQAN-CETD6W3-FFLJOUZ-RANRYYN-C2SRPH3-3VTAMQB";
                  addresses = [ "dynamic" ];
                  autoAcceptFolders = true;
                };
                folders.Projects = {
                  id = "zd26e-jmupe";
                  path = "/home/chris/Projects";
                  devices = [ "macbook" ];
                  fsWatcherDelayS = 1;
                  fsWatcherEnabled = true;
                  versioning = {
                    type = "staggered";
                    params = {
                      cleanInterval = "3600";
                      maxAge = "2592000"; # 30 days
                    };
                  };
                };
              };
            };

            # Tailscale
            services.tailscale = {
              enable = true;
              openFirewall = true;
              useRoutingFeatures = "server";
              extraUpFlags = [
                "--ssh"
                "--advertise-exit-node"
                "--advertise-routes=192.168.0.0/24"
                "--accept-dns=false"
              ];
            };

            environment.systemPackages = with pkgs; [
              just                     # Task runner (Justfile)
              cifs-utils               # SMB mounts for Synology NAS
              libvirt-dbus             # D-Bus bridge for libvirt (Cockpit dependency)
              ghostty.terminfo         # Terminal definitions for SSH from Ghostty
            ];

            # Other
            nixpkgs.config.allowUnfree = true;
            nix.settings = {
              experimental-features = [ "nix-command" "flakes" ];
              auto-optimise-store = true;
            };

            # System Version
            system.stateVersion = "25.05";

            # Time Zone
            time.timeZone = "Europe/Bucharest";
          })
        ];
      };
    };
}
