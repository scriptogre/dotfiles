# darwin-rebuild switch --flake .#macbook
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
          { system.primaryUser = "chris"; }

          mac-app-util.darwinModules.default

          # Base nix-darwin configuration as an inline module
          ({ pkgs, config, ... }: {
            nixpkgs.config.allowUnfree  = true;
            nixpkgs.config.allowBroken = true;
            nixpkgs.hostPlatform       = system;
            nix.settings.experimental-features = "nix-command flakes";

            environment.systemPackages = with pkgs; [
              caddy
              gh
              git
              iterm2
              just
              neovim
              sqlite
              tailscale
              terraform
              uv
            ];

            fonts.packages = with pkgs; [
              nerd-fonts.jetbrains-mono
            ];

            homebrew.enable = true;
            homebrew.casks = [
              "1password"
              "1password-cli"
              "alfred"
              "alt-tab"
              "anydesk"
              "betterdisplay"
              "bettertouchtool"
              "brave-browser"
              "chatgpt"
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
            homebrew.onActivation.cleanup = "zap";
              system.stateVersion = 6;
          })

          # Nix-homebrew module
          nix-homebrew.darwinModules.nix-homebrew {
            nix-homebrew.enable        = true;
            nix-homebrew.enableRosetta = true;
            nix-homebrew.user          = "chris";
          }
        ];
      };
    };
}