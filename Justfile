switch: update
    sudo darwin-rebuild switch --flake .#macbook

update:
    nix flake update
