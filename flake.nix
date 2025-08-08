{
  description = "Chris's homelab - environment configuration for all machines";

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

  outputs = { self, nixpkgs, home-manager, nix-darwin, nix-homebrew, mac-app-util }:
    let
      # Import common configuration module
      commonModule = import ./modules/common.nix;
      
      # Shared inputs for host configurations
      sharedArgs = {
        inherit nixpkgs home-manager nix-darwin nix-homebrew mac-app-util;
        inherit commonModule;
      };
    in
    {
      # macOS System Configurations
      darwinConfigurations = {
        macbook = import ./hosts/macbook.nix sharedArgs;
        dell = import ./hosts/dell.nix { inherit nixpkgs home-manager nix-darwin nix-homebrew mac-app-util; };
      };

      # NixOS System Configurations  
      nixosConfigurations = {
        # acasa = import ./hosts/acasa.nix sharedArgs; # Temporarily disabled - needs hardware config
        # betania is now a standalone flake in hosts/betania.nix
      };

      # Home Manager Configurations
      homeConfigurations = {
        # macOS
        "chris@macbook" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.aarch64-darwin;
          modules = [
            {
              home.username = "chris";
              home.homeDirectory = "/Users/chris";
            }
            (let 
              pkgs = nixpkgs.legacyPackages.aarch64-darwin;
              common = commonModule { inherit pkgs; };
            in common.mkHomeConfig {
              extraPackages = with pkgs; [
                iterm2
                nerd-fonts.jetbrains-mono
              ];
            })
          ];
        };
      };
    };
}