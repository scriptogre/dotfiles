{
  description = "Chris's MacBook configuration";

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

  outputs = { self, nixpkgs, home-manager, nix-darwin, nix-homebrew, mac-app-util, ... }@inputs: {
    darwinConfigurations."macbook" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        # System configuration
        {
          nixpkgs.config.allowUnfree = true;
          nix.enable = false;
          system.stateVersion = 6;

          networking.hostName = "macbook";

          system.primaryUser = "chris";

          users.users.chris.home = "/Users/chris";

          services.tailscale.enable = true;
        }

        # Homebrew
        nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            enable = true;
            enableRosetta = true;
            user = "chris";
          };
          homebrew = {
            enable = true;
            onActivation = {
                autoUpdate = true;
                cleanup = "zap";
                upgrade = true;
            };
            casks = [
              "1password"
              "alfred"
              "alt-tab"
              "anydesk"
              "betterdisplay"
              "bettertouchtool"
              "brave-browser"
              "chatgpt"
              "claude"
              "discord"
              "firefox"
              "google-chrome"
              "volume-control"
              "jetbrains-toolbox"
              "karabiner-elements"
              "jordanbaird-ice"
              "ledger-wallet"
              "lm-studio"
              "mos"
              "notunes"
              "nordvpn"
              "obs"
              "obsidian"
              "omnidisksweeper"
              "orbstack"
              "parallels"
              "proton-mail"
              "pycharm"
              "spotify"
              "synology-drive"
              "telegram"
              "todoist-app"
              "vibetunnel"
            ];
          };
        }

        # Home Manager
        home-manager.darwinModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.users.chris = { pkgs, ... }: {
            imports = [ ../../common/home.nix ];

            home.username = "chris";
            home.homeDirectory = "/Users/chris";

            # macOS-specific packages
            home.packages = with pkgs; [
              iterm2
            ];
          };
        }

        mac-app-util.darwinModules.default
      ];
    };
  };
}
