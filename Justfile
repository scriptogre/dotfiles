# Rebuild current host
rebuild hostname=`hostname -s`:
    nix flake update --flake ./hosts/{{ hostname }}
    sudo {{ if os() == "macos" { "darwin-rebuild" } else {"nixos-rebuild"}  }} switch --flake ./hosts/{{ hostname }}#{{ hostname }}

check hostname=`hostname -s`:
  nix flake check ./hosts/{{ hostname }}

thinkcentre:
  rsync -av --delete ./ chris@192.168.0.12:/home/chris/dotfiles/
  ssh chris@192.168.0.12 "cd /home/chris/dotfiles/hosts/thinkcentre && sudo nixos-rebuild switch --flake .#thinkcentre"
