# Rebuild current host
rebuild:
    nix flake update
    sudo darwin-rebuild switch --flake .
