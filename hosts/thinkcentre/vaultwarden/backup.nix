# Hourly Vaultwarden backup. The script holds no config — everything comes
# from this module's Environment block. Single source of truth: this file.

{ pkgs, ... }:

let
  scriptPath = "/home/chris/Projects/dotfiles/hosts/thinkcentre/vaultwarden/scripts/backup.sh";
  ageRecipient = "/home/chris/Projects/dotfiles/hosts/thinkcentre/vaultwarden/backup.age.pub";
  # Pull the off-site Synology IP from the single source of truth so that
  # rename in aliases.nix → IP change propagates automatically. The script
  # runs as root, which doesn't see chris's ~/.ssh/config.d/hosts alias, so
  # we use user@IP directly instead of the alias.
  aliases = import ../../../common/network/aliases.nix;
  synology2 = "chris@${aliases.hosts.synology-2.ip}";
in
{
  systemd.services.vaultwarden-backup = {
    description = "Vaultwarden encrypted backup → local + both Synologys";
    after = [ "docker.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ docker gnutar zstd age rsync openssh coreutils findutils gnugrep gnused gawk bash ];
    serviceConfig = {
      Type = "oneshot";
      Environment = [
        "VW_DATA_DIR=/var/lib/vaultwarden/data"
        "VW_LOCAL_DIR=/var/backups/vaultwarden"
        "VW_STATE_FILE=/var/lib/vaultwarden/last-backup.json"
        "VW_AGE_RECIPIENT=${ageRecipient}"
        "VW_SYNOLOGY1_DIR=/mnt/nas/homes/chris/backups/vaultwarden"
        "VW_SYNOLOGY2_HOST=${synology2}"
        "VW_SYNOLOGY2_PATH=/volume1/homes/chris/backups/vaultwarden"
        "VW_RETENTION_DAYS=7"
      ];
      ExecStart = scriptPath;
      # Runs as root: needs to read /var/lib/vaultwarden (owned by container
      # uid) and exec docker. SSH out uses /root/.ssh/id_ed25519.
      User = "root";
    };
  };

  systemd.timers.vaultwarden-backup = {
    description = "Vaultwarden backup hourly";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
      Unit = "vaultwarden-backup.service";
      # Re-run missed timers after sleep/downtime.
      Persistent = true;
    };
  };
}
