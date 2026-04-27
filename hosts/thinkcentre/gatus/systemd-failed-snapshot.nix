# Periodically writes the list of failed systemd units to a file the
# gatus-helper container can read (via its /:/hostfs:ro mount). This avoids
# giving the container D-Bus access just to query systemctl.

{ pkgs, ... }:

{
  systemd.services.systemd-failed-snapshot = {
    description = "Snapshot list of failed systemd units for Gatus";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "systemd-failed-snapshot" ''
        ${pkgs.systemd}/bin/systemctl --failed --no-legend --plain \
            | ${pkgs.gawk}/bin/awk '{print $1}' > /run/systemd-failed.txt
      '';
    };
  };

  systemd.timers.systemd-failed-snapshot = {
    description = "Snapshot failed units every minute";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s";
      OnUnitActiveSec = "1min";
      Unit = "systemd-failed-snapshot.service";
    };
  };
}
