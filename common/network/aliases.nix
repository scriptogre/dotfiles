# Single source of truth for hostname → IP mappings across the homelab.
#
# Consumers (all read this file directly; never duplicate values elsewhere):
#   - common/home.nix              → ~/.ssh/config.d/hosts (Mac + ThinkCentre)
#   - hosts/thinkcentre/flake.nix  → networking.hosts (/etc/hosts on ThinkCentre)
#   - hosts/thinkcentre/adguard/   → AdGuard DNS rewrites (auto-reconciled by
#                                    a systemd timer; no manual sync needed)
#
# To rename a host: change its key here. Rebuild on each NixOS host. Within
# 5 minutes the AdGuard timer brings AdGuard's rewrites into agreement.
#
# Adding `ssh = { user = "..."; }` to a host opts it into the SSH config on
# the consumer machines. Hosts without `ssh` get DNS-only treatment.

{
  hosts = {
    thinkcentre = { ip = "192.168.0.12";   ssh = { user = "chris"; }; };
    synology    = { ip = "192.168.0.14";   ssh = { user = "chris"; }; };
    synology-2  = { ip = "100.114.162.56"; ssh = { user = "chris"; }; };  # Tailscale IP — only one routable from ThinkCentre
    pi          = { ip = "192.168.0.41";   ssh = { user = "chris"; }; };
    macbook     = { ip = "192.168.0.29"; };
    router      = { ip = "192.168.0.1";  };
  };

  # Wildcards — only AdGuard understands these; SSH and /etc/hosts skip them.
  wildcards = {
    "*.christiantanul.com" = "192.168.0.12";
    "*.alexandrutanul.com" = "192.168.0.12";
  };
}
