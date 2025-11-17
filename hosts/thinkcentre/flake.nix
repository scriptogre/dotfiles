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
        ({ pkgs, ... }: {

            # Users
            users.users.chris = {
              isNormalUser = true;
              extraGroups = [ "wheel" "networkmanager" "docker" ];
              password = "chris";
            };
            security.sudo.wheelNeedsPassword = false;

            # Bootloader
            boot.loader.systemd-boot.enable = true;
            boot.loader.efi.canTouchEfiVariables = true;

            # Networking
            networking.hostName = "thinkcentre";
            networking.networkmanager.enable = true;
            networking.firewall = {
              enable = true;
              # Trust all traffic from these interfaces (no filtering)
              trustedInterfaces = [ "tailscale0" "wlo1" ];
              allowedTCPPorts = [
                3389  # RDP
                80    # HTTP
                443   # HTTPS
              ];
            };

            # Docker
            virtualisation.docker.enable = true;

            # Desktop Environment
            services.xserver.enable = true;
            services.displayManager.gdm.enable = true;
            services.desktopManager.gnome.enable = true;

            # Remote Desktop Protocol (RDP)
            services.gnome.gnome-remote-desktop.enable = true;
            services.xrdp = {
              enable = true;
              defaultWindowManager = "${pkgs.gnome-session}/bin/gnome-session";
            };

            # Tailscale
            services.tailscale = {
              enable = true;
              openFirewall = true;
              useRoutingFeatures = "client";
              extraUpFlags = [
                "--accept-routes"
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