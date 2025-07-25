{ nixpkgs, home-manager, nix-darwin, nix-homebrew, mac-app-util, commonPackages, homeConfig }:

nix-darwin.lib.darwinSystem {
  system = "aarch64-darwin";
  modules = [
    # System configuration
    {
      nixpkgs.config.allowUnfree = true;
      nix.settings.experimental-features = [ "nix-command" "flakes" ];
      networking.hostName = "macbook";
      system.stateVersion = 6;
      system.primaryUser = "chris";
      services.tailscale.enable = true;
      users.users.chris.home = "/Users/chris";
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
          "1password-cli"
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
          "itunes-volume-control"
          "jetbrains-toolbox"
          "karabiner-elements"
          "jordanbaird-ice"
          "ledger-live"
          "lm-studio"
          "mos"
          "notunes"
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
        ];
      };
    }

    # Home Manager
    home-manager.darwinModules.home-manager
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "backup";
      home-manager.users.chris = { pkgs, ... }: (
        {
          home.stateVersion = "25.05";
          home.username = "chris";
          home.homeDirectory = "/Users/chris";
        } // homeConfig {
          inherit pkgs;
          extraPackages = with pkgs; [
            iterm2
            nerd-fonts.jetbrains-mono
          ];
        }
      );
    }

    mac-app-util.darwinModules.default
  ];
}