# Reconciles AdGuard DNS rewrites against common/network/aliases.nix on every
# listed endpoint. Strict mode: any rewrite not in aliases.nix is deleted.
# Edit aliases.nix to make changes — never the AdGuard web UI.

{ pkgs, ... }:

let
  endpoints = [
    "https://adguard.christiantanul.com"
    "https://adguard-2.christiantanul.com"
  ];
  aliasesFile = "/home/chris/Projects/dotfiles/common/network/aliases.nix";
  scriptPath  = "/home/chris/Projects/dotfiles/hosts/thinkcentre/adguard/sync-rewrites.sh";
  envFile     = "/home/chris/Projects/dotfiles/hosts/thinkcentre/adguard/.env";
in
{
  systemd.services.adguard-rewrites-sync = {
    description = "Reconcile AdGuard DNS rewrites with aliases.nix on all endpoints";
    after = [ "docker.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ nix curl jq coreutils bash ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = envFile;
      # Wrap space-containing values in literal double-quotes so systemd's
      # Environment= parser treats each as a single value (it splits on
      # whitespace by default, and NixOS doesn't auto-quote).
      Environment = [
        "ADGUARD_USER=chris"
        ''ADGUARD_URLS="${builtins.concatStringsSep " " endpoints}"''
        "ALIASES_FILE=${aliasesFile}"
        # ThinkCentre's resolver is the router (not AdGuard), so without
        # --resolve overrides the request would go through Cloudflare and
        # hit Caddy's lan-only rejection.
        ''CURL_RESOLVES="adguard.christiantanul.com:443:192.168.0.12 adguard-2.christiantanul.com:443:192.168.0.12"''
      ];
      ExecStart = scriptPath;
      User = "chris";
    };
  };

  systemd.timers.adguard-rewrites-sync = {
    description = "Reconcile AdGuard DNS rewrites every 5 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "5min";
      Unit = "adguard-rewrites-sync.service";
    };
  };
}
