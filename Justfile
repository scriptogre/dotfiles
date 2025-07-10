switch: update
    sudo darwin-rebuild switch --flake .#macbook

update:
    nix flake update

update-nix-2:
    nix run github:nix-community/nixos-anywhere -- --flake .#default --target-host chris@192.168.68.111