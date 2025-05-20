# ./flake.nix
{
  description = "My nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager"; # Or specific release branch
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
      # No need to follow nixpkgs here unless it exports a pkgs itself
    };

    mac-app-util = {
      url = "github:hraban/mac-app-util";
      # No need to follow nixpkgs here
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, nix-darwin, nix-homebrew, mac-app-util, ... }:
    let
      system = "aarch64-darwin";
      username = "chris";  # User for whom Home Manager and nix-homebrew will be configured
    in
    {
      darwinConfigurations.macbook = nix-darwin.lib.darwinSystem {
        inherit system;
        # Pass inputs to modules, so they can access e.g. inputs.nixpkgs
        # or inputs.self (if you added self to inputs for local paths)
        specialArgs = { inherit inputs username system; };

        modules = [
          # Import the system-level Darwin configuration
          ./darwin-configuration.nix

          # Home Manager module for nix-darwin
          home-manager.darwinModules.home-manager
          {
            # Configure Home Manager itself
            home-manager = {
              useGlobalPkgs = true; # Use system nixpkgs for HM, saves evaluation
              useUserPackages = true; # Install HM packages to /etc/profiles/per-user
              # Extra special arguments to pass to home.nix, like inputs
              extraSpecialArgs = { inherit inputs username system; };
              users.${username} = import ./home.nix;
            };
          }

          # Nix-homebrew module
          nix-homebrew.darwinModules.nix-homebrew
          {
            # Configure nix-homebrew
            nix-homebrew = {
              enable = true;
              enableRosetta = true; # If you need Rosetta for some brews/casks
              user = username; # Specify the user for Homebrew
            };
          }

          # Mac App Util module
          mac-app-util.darwinModules.default
          # No specific config needed here unless you override its options

          # Inline module to set primaryUser if not set elsewhere
          # Though typically system.activationScripts.postActivation might be better
          # or just ensure your user exists.
          ({ lib, ... }: {
            # This ensures nix-darwin knows the primary user, useful for some services
            # or if you have `users.users.<name>.createHome = true;`
            # However, Home Manager and nix-homebrew handle the user 'chris' specifically.
            # This might be redundant if 'chris' is already the logged-in user building this.
            users.users.${username}.home = "/Users/${username}"; # Ensure user dir is known
            # system.activationScripts.userActivation.text = ''
            #   # Ensure the primary user for some system services if needed
            #   echo "Primary user set to ${username}"
            # '';
          })

        ];
      };

      # Expose Home Manager configurations separately if you want to build them independently
      # (e.g., for other systems or users not managed by darwinConfigurations)
      # homeConfigurations."${username}" = home-manager.lib.homeManagerConfiguration {
      #   pkgs = nixpkgs.legacyPackages.${system};
      #   extraSpecialArgs = { inherit inputs username; };
      #   modules = [ ./home.nix ];
      # };
    };
}