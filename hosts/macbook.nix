{ nixpkgs, home-manager, nix-darwin, nix-homebrew, mac-app-util, commonModule }:

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

      # Safari configuration - only settings that differ from defaults
      system.activationScripts.configureSafari.text = ''
        echo "Configuring Safari settings..."
        
        # Disable all AutoFill features (we use 1Password)
        defaults write com.apple.Safari AutoFillCreditCardData -bool false
        defaults write com.apple.Safari AutoFillFromAddressBook -bool false
        defaults write com.apple.Safari AutoFillFromiCloudKeychain -bool false
        defaults write com.apple.Safari AutoFillMiscellaneousForms -bool false
        defaults write com.apple.Safari AutoFillPasswords -bool false
        
        # Developer tools
        defaults write com.apple.Safari IncludeDevelopMenu -bool true
        defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
        
        # Interface preferences
        defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
        defaults write com.apple.Safari NewTabBehavior -int 1
        defaults write com.apple.Safari NewWindowBehavior -int 1
        defaults write com.apple.Safari OpenNewTabsInFront -bool true
        defaults write com.apple.Safari SuppressSearchSuggestions -bool true
        defaults write com.apple.Safari ShowStandaloneTabBar -bool false

        echo "Safari settings configured. Restart Safari to apply changes."
      '';
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
        masApps = {
          "AdGuard for Safari" = 1440147259;
          "1Password for Safari" = 1569813296;
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
      home-manager.users.chris = { pkgs, ... }: 
        let
          common = commonModule { inherit pkgs; };
        in
        {
          home.username = "chris";
          home.homeDirectory = "/Users/chris";
        } // common.mkHomeConfig {
          extraPackages = with pkgs; [
            iterm2
            nerd-fonts.jetbrains-mono
          ];
        };
    }

    mac-app-util.darwinModules.default
  ];
}