# Daily 1Password → encrypted → both Synologys.
# The script skips silently when 1Password.app is locked.

{ config, ... }:

let
  home = config.users.users.${config.system.primaryUser}.home;
  scriptPath = "${home}/Projects/dotfiles/hosts/macbook/onepassword-export/export.sh";
  logFile = "${home}/Library/Logs/onepassword-export.log";
in
{
  launchd.user.agents.onepassword-export = {
    serviceConfig = {
      # Daily at 13:00 local — likely the laptop is awake and 1P is unlocked.
      StartCalendarInterval = [ { Hour = 13; Minute = 0; } ];
      StandardOutPath = logFile;
      StandardErrorPath = logFile;
      RunAtLoad = false;
    };
    script = ''
      # Make sure op, jq, age, zstd, etc. are findable.
      export PATH="/etc/profiles/per-user/${config.system.primaryUser}/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
      exec ${scriptPath}
    '';
  };
}
