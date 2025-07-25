# Rebuild current host (auto-detect hostname)
rebuild: update
    if [[ "$(uname)" == "Darwin" ]]; then \
        sudo darwin-rebuild switch --flake .; \
    else \
        sudo nixos-rebuild switch --flake .; \
    fi

# Update flakes
update:
    nix flake update