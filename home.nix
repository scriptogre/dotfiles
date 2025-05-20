{ pkgs, config, lib, ... }: # config here is Home Manager's config, inputs is from specialArgs

{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "chris";
  home.homeDirectory = "/Users/chris";

  # This value determines the Home Manager release that your
  # configuration is compatible with. This helps avoid breakage
  # when a new Home Manager release introduces backwards
  # incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  # Version 25.05 is used in examples for Home Manager 25.11 manual.
  # Update this according to the Home Manager version you are tracking.
  home.stateVersion = "25.05"; # Or keep "23.11" if you haven't updated HM input

  # Let Home Manager install and manage itself.
  # This is only needed for standalone Home Manager, not when used as a module.
  # programs.home-manager.enable = true; # REMOVE THIS LINE

  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
    # CLI tools moved from systemPackages
    caddy
    gh
    # git is managed by programs.git below, but having it here is harmless
    # and ensures it's in the PATH if programs.git.package is overridden.
    git
    iterm2 # iTerm2 can also be a cask, but if you prefer the Nix package
    just
    neovim
    sqlite
    tailscale # CLI, the GUI app is usually a cask
    terraform
    uv

    # Fonts (can also be system-wide, but user-specific is fine too)
    nerd-fonts.jetbrains-mono
  ];

  # Git Configuration
  programs.git = {
    enable = true;
    userName = "scriptogre";
    userEmail = "git@christiantanul.com";
    extraConfig = {
      core = {
        excludesfile = "${config.home.homeDirectory}/.config/git/ignore";
      };
      init.defaultBranch = "master";
      pull.rebase = true;
    };
  };
  # Global gitignore
  home.file.".config/git/ignore" = {
    source = ./gitignore;
  };
}