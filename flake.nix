{
  description = "My nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";
    mac-app-util.url = "github:hraban/mac-app-util";
  };

  outputs = inputs@{ self, nixpkgs, nix-darwin, nix-homebrew, mac-app-util, ... }:
    let
      system = "aarch64-darwin";
    in
    {
      darwinConfigurations.macbook = nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = { inherit inputs; };

        modules = [
          mac-app-util.darwinModules.default

          # Base nix-darwin configuration as an inline module
          ({ pkgs, config, ... }: {
            nixpkgs.config = {
              allowUnfree = true;
              allowBroken = true;
            };
            nixpkgs.hostPlatform = system;

            nix.settings.experimental-features = "nix-command flakes";

            environment.systemPackages = with pkgs; [
              caddy
              gh
              git
              just
              neovim
              sqlite
              tailscale
              terraform
              uv
            ];

            homebrew = {
              enable = true;
              casks = [
                "1password"
                "1password-cli"
                "alfred"
                "alt-tab"
                "anydesk"
                "betterdisplay"
                "bettertouchtool"
                "brave-browser"
                "discord"
                "itunes-volume-control"
                "karabiner-elements"
                "ledger-live"
                "mos"
                "notunes"
                "obs"
                "obsidian"
                "omnidisksweeper"
                "orbstack"
                "parallels"
                "proton-mail"
                "pycharm"
                "slack"
                "spotify"
                "synology-drive"
                "telegram"
                "zoom"
              ];
              onActivation.cleanup = "zap";
            };
            system.stateVersion = 6;
          })

          # Nix-homebrew module
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              enableRosetta = true;
              user = "chris";
            };
          }
        ];
      };
    };
}