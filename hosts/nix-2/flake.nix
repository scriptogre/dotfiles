{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  
  outputs = { nixpkgs, ... }: {
    nixosConfigurations.default = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        {
          nix.settings.experimental-features = [ "nix-command" "flakes" ];

          networking.hostName = "nix-2";

          users.users.chris = {
            isNormalUser                = true;
            extraGroups                 = [ "wheel" ];
            initialPassword             = "chris";
            openssh.authorizedKeys.keys = [
                "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDUJWuWXCZpiPQSwRZgOU6baccQZ14+lTJqUeMtfNE1jZcvtucF++3S7CTH7mHngFbI71/Io+ICqEZAkYBnu72CMwPXOwFyj5nerhQK5uX6KWGcLMXYwH4v43jWVdv/Xe/Dk3xshD3yevgeGzgQZxmWlko6hgr+0sGU7eJBFbfx8ILKTOLbXSVyBCx5xK37vaa8x7ZUB7oASj0hLH6YXs+BjPpwQuXCnNx8exMwMWajfaJ5gqaIyZLxyXJxgt8gbMTeQNN8fbavxiZozWwFbC50kXcHR8lKsGvXgqA5WlU55RdYoEzSTWflw6bsyEaFNbXBt2asAVDNBMPS1/aP8vdlKolU1Sqd/dMFYu1WLQ+Q705G//+iwEWeiZpg/m9+8CSU6OD0toRaUneC11CmDXTJjS89giIbofpz900+j2WOcSbAOEGHjCEl+qDl4bWXndF9itqgblQjFDysgJ3ZI4PAR4OCB8GyNY5UUoKg2HAB8H50gNdV0pHS2ysPh8c3Me/cGfbBYVUjzzsmxEd4VGzCP098ippMpgK/K/Q9TFtuaxEZZ3jOb0/GU10JjatgWYfULzXyXRkyptZDkGyGR+6I0YfcEmFy8hInf1oXS8keDHGAxznXn3EhNXH6xQuaJM4zIOE60CUUdBC3Iz1T7Kmidc9BNDGz/ggJmnD66RzTBw=="
            ];
          };

          # Wheel-wide NOPASSWD sudo
          security.sudo.wheelNeedsPassword = false;

          services.openssh = {
            enable                          = true;
            openFirewall                    = true;
            passwordAuthentication          = false;
            challengeResponseAuthentication = false;
            permitRootLogin                 = "no";
          };

          services.tailscale = {
            enable             = true;
            openFirewall       = true;
            useRoutingFeatures = true;
          };

          # Ensure 24/7 running
          services.logind = {
              lidSwitch               = "ignore";
              lidSwitchExternalPower  = "ignore";
              extraConfig = ''
                IdleAction=ignore
              '';
            };
          systemd.sleep.extraConfig = ''
              AllowSuspend=no
              AllowHibernation=no
              AllowHybridSleep=no
              AllowSuspendThenHibernate=no
          '';

          # Keep CPU at full speed
          powerManagement.cpuFreqGovernor = "performance";
          # Monitor CPU temperature
          services.thermald.enable = true;

          environment.systemPackages = with pkgs; [
            git
          ];

          # Boot configuration
          boot.loader = {
            systemd-boot.enable      = true;  # Simple UEFI loader
            efi.canTouchEfiVariables = true;  # Let it edit NVRAM
          };

          system.stateVersion = "24.11";
        }
      ];
    };
  };
}
