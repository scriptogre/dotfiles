{ nixpkgs, home-manager, nix-darwin, nix-homebrew, mac-app-util }:


nix-darwin.lib.darwinSystem {
  system = "x86_64-darwin"; # Assuming Dell is Intel-based
  modules = [
    # System configuration
    {
      nixpkgs.config.allowUnfree = true;
      nix.settings.experimental-features = [ "nix-command" "flakes" ];
      networking.hostName = "dell";
      system.stateVersion = 6;
      system.primaryUser = "chris";
      users.users.chris.home = "/Users/chris";
    }

    # Home Manager
    home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "backup";
      home-manager.users.chris = { pkgs, ... }: {
        home.stateVersion = "25.05";
        home.username = "chris";
        home.homeDirectory = "/Users/chris";
        
        # Minimal package set - customize as needed
        home.packages = with pkgs; [
          git
          curl
          htop
        ];
      };
    }
  ];
}