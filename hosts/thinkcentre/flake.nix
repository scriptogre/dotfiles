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
        # Home Manager
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.users.chris = { pkgs, ... }: {
            imports = [ ../../common/home.nix ];
            home.username = "chris";
            home.homeDirectory = "/home/chris";
          };
        }

        # System configuration
        ({ pkgs, config, ... }: {

            # Users
            users.users.chris = {
              isNormalUser = true;
              shell = pkgs.zsh;
              extraGroups = [ "wheel" "networkmanager" "docker" "video" "render" ];
              password = "chris";
              openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINLGEYgN5pbs2u1eMfTnpKUqHCm8fPuC/vSeV4Ht0KyL" # home_network_key_2 (1Password)
              ];
            };
            programs.zsh.enable = true;
            security.sudo.wheelNeedsPassword = false;

            # Bootloader
            boot.loader.systemd-boot.enable = true;
            boot.loader.efi.canTouchEfiVariables = true;

            # Networking
            networking.hostName = "thinkcentre";
            networking.networkmanager.enable = true;
            networking.wireless.enable = false;
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
                3389   # RDP
                80     # HTTP
                443    # HTTPS
                32400  # Plex
              ];
            };

            # Intel GPU (QuickSync hardware transcoding)
            hardware.graphics = {
              enable = true;
              extraPackages = with pkgs; [
                intel-media-driver  # VAAPI for 12th/13th gen+
                vpl-gpu-rt          # Intel Video Processing Library
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
            fileSystems."/mnt/nas/photos/chris" = {
              device = "//192.168.0.14/homes/chris/Photos";
              fsType = "cifs";
              options = [
                "credentials=/var/lib/nas-credentials" "uid=1000" "gid=100"
                "nofail" "x-systemd.automount" "x-systemd.idle-timeout=60"
                "x-systemd.device-timeout=5s" "x-systemd.mount-timeout=5s"
              ];
            };
            fileSystems."/mnt/nas/photos/ana" = {
              device = "//192.168.0.14/homes/ana/Photos";
              fsType = "cifs";
              options = [
                "credentials=/var/lib/nas-credentials" "uid=1000" "gid=100"
                "nofail" "x-systemd.automount" "x-systemd.idle-timeout=60"
                "x-systemd.device-timeout=5s" "x-systemd.mount-timeout=5s"
              ];
            };

            # Docker
            virtualisation.docker.enable = true;

            # Plex Media Server (with Intel QuickSync)
            virtualisation.oci-containers = {
              backend = "docker";
              containers.plex = {
                image = "ghcr.io/hotio/plex:latest";
                environment = {
                  TZ = "Europe/Bucharest";
                  PUID = "1000";
                  PGID = "100";
                };
                volumes = [
                  "/var/lib/plex:/config"
                  "/mnt/nas/media:/data/media:ro"
                  "/mnt/nas/photos:/data/photos:ro"
                ];
                extraOptions = [
                  "--network=host"
                  "--device=/dev/dri:/dev/dri"
                  "--tmpfs=/transcode"
                ];
              };
            };

            # Desktop Environment
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

            # SSH
            services.openssh = {
              enable = true;
              settings = {
                PasswordAuthentication = false;
                PermitRootLogin = "no";
              };
            };

            # Tailscale
            services.tailscale = {
              enable = true;
              openFirewall = true;
              useRoutingFeatures = "client";
              extraUpFlags = [
                "--ssh"
              ];
            };

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
