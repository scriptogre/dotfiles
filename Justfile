# Rebuild current host
rebuild hostname=`hostname -s`:
    nix flake update --flake ./hosts/{{ hostname }}
    sudo {{ if os() == "macos" { "darwin-rebuild" } else {"nixos-rebuild"}  }} switch --flake ./hosts/{{ hostname }}#{{ hostname }}

check hostname=`hostname -s`:
  nix flake check ./hosts/{{ hostname }}

# Rebuild ThinkCentre (git push triggers webhook pull; this just triggers nixos-rebuild)
thinkcentre:
  ssh thinkcentre just


# Build patched SpacetimeDB Docker image on thinkcentre (native x86_64)
spacetimedb-build:
  ssh chris@192.168.0.12 'if [ ! -d ~/SpacetimeDB ]; then git clone https://github.com/scriptogre/SpacetimeDB.git ~/SpacetimeDB; fi'
  ssh chris@192.168.0.12 'cd ~/SpacetimeDB && git fetch origin && git checkout hypermedia && git pull origin hypermedia'
  ssh chris@192.168.0.12 'cd ~/SpacetimeDB && docker build -t ghcr.io/scriptogre/spacetimedb:hypermedia .'
