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
          home-manager.users.chris = { pkgs, lib, ... }: {
            imports = [ ../../common/home.nix ];
            home.username = "chris";
            home.homeDirectory = "/home/chris";
            dconf.settings = {
              "org/gnome/desktop/session" = {
                idle-delay = lib.hm.gvariant.mkUint32 0;
              };
              "org/gnome/desktop/screensaver" = {
                lock-enabled = false;
              };
            };
            home.file."Justfile".text = ''
              default: rebuild

              # Rebuild NixOS from flake
              rebuild:
                  sudo nixos-rebuild switch --flake ~/dotfiles/hosts/thinkcentre

              # Show running containers
              status:
                  docker ps

              # View container logs
              logs name:
                  docker logs -f --tail 100 {{name}}

              # Restart a container
              restart name:
                  docker restart {{name}}

              # Stop a container
              stop name:
                  docker stop {{name}}

              # Start a container
              start name:
                  docker start {{name}}

              # Start Windows gaming VM (takes over GPU)
              game:
                  virsh start win11

              # Stop Windows gaming VM (returns GPU to host)
              stop-game:
                  virsh shutdown win11
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
              ];
            };
            programs.zsh.enable = true;
            security.sudo.wheelNeedsPassword = false;

            # Bootloader
            boot.loader.systemd-boot.enable = true;
            boot.loader.systemd-boot.consoleMode = "auto";
            boot.loader.efi.canTouchEfiVariables = true;

            # IOMMU for GPU passthrough + split lock fix for Windows VM performance
            boot.kernelParams = [
              "intel_iommu=on"
              "iommu=pt"
              "split_lock_detect=off"
            ];

            # VFIO modules for GPU passthrough (loaded but don't auto-bind — hook script handles binding)
            boot.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];

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
                3389   # RDP
                80     # HTTP
                443    # HTTPS
                3000   # SpacetimeDB
                5900   # VNC (Windows VM install)
                32400  # Plex
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

            # Docker
            virtualisation.docker.enable = true;

            # Libvirt/QEMU for Windows gaming VM with GPU passthrough
            virtualisation.libvirtd = {
              enable = true;
              qemu = {
                package = pkgs.qemu_kvm;
                runAsRoot = true;
                swtpm.enable = true;
              };
            };

            # Libvirt hook: bind/unbind dGPU (RTX 3060 Ti) for VM passthrough
            # iGPU stays on host for GDM + Plex QuickSync
            environment.etc."libvirt/hooks/qemu" = {
              mode = "0755";
              text = ''
                #!/bin/sh
                GUEST_NAME="$1"
                HOOK_NAME="$2"
                STATE_NAME="$3"

                DGPU_PCI="0000:01:00.0"
                DGPU_AUDIO_PCI="0000:01:00.1"

                if [ "$GUEST_NAME" != "win11" ]; then
                  exit 0
                fi

                bind_to_vfio() {
                  local pci="$1"
                  local current_driver="$2"
                  if [ -n "$current_driver" ] && [ -e "/sys/bus/pci/drivers/$current_driver/$pci" ]; then
                    echo "$pci" > "/sys/bus/pci/drivers/$current_driver/unbind"
                  fi
                  echo "vfio-pci" > "/sys/bus/pci/devices/$pci/driver_override"
                  echo "$pci" > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || true
                }

                unbind_from_vfio() {
                  local pci="$1"
                  if [ -e "/sys/bus/pci/drivers/vfio-pci/$pci" ]; then
                    echo "$pci" > /sys/bus/pci/drivers/vfio-pci/unbind
                  fi
                  echo "" > "/sys/bus/pci/devices/$pci/driver_override"
                }

                if [ "$HOOK_NAME" = "prepare" ] && [ "$STATE_NAME" = "begin" ]; then
                  modprobe vfio-pci

                  # Bind dGPU + audio to vfio-pci
                  bind_to_vfio "$DGPU_PCI" "nouveau"
                  bind_to_vfio "$DGPU_AUDIO_PCI" "snd_hda_intel"

                elif [ "$HOOK_NAME" = "release" ] && [ "$STATE_NAME" = "end" ]; then
                  # Release dGPU from vfio-pci
                  unbind_from_vfio "$DGPU_PCI"
                  unbind_from_vfio "$DGPU_AUDIO_PCI"

                  sleep 1

                  # Rescan PCI — nouveau reclaims the dGPU
                  echo 1 > /sys/bus/pci/rescan
                fi
              '';
            };

            # Plex Media Server (with Intel QuickSync) + SpacetimeDB
            virtualisation.oci-containers = {
              backend = "docker";
              containers.spacetimedb = {
                image = "clockworklabs/spacetime:v1.12.0";
                cmd = [ "start" ];
                ports = [ "3000:3000" ];
                volumes = [ "/var/lib/spacetimedb:/stdb" ];
              };
              containers.plex = {
                image = "ghcr.io/hotio/plex:latest";
                environment = {
                  TZ = "Europe/Bucharest";
                  PUID = "1000";
                  PGID = "100";
                  ADVERTISE_IP = "https://plex.christiantanul.com:443";
                  ALLOWED_NETWORKS = "192.168.0.0/255.255.255.0";
                };
                volumes = [
                  "/var/lib/plex:/config"
                  "/mnt/nas/media:/data/media:ro"
                ];
                extraOptions = [
                  "--network=host"
                  "--device=/dev/dri:/dev/dri"
                  "--tmpfs=/transcode"
                ];
              };
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

            # Cockpit web UI for managing VMs
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

            # libvirt-dbus system service (required for Cockpit VM management)
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

            environment.systemPackages = with pkgs; [
              cockpit-machines         # VM management in Cockpit web UI
              libvirt-dbus             # D-Bus bridge for libvirt (Cockpit dependency)
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
