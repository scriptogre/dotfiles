# 1Password daily export

Mirrors your entire 1Password vault contents to both Synologys, encrypted
with the same `age` key as the Vaultwarden backups (private key in 1Password
under "Vaultwarden Backup Age Key"). Hedges against losing access to your
1Password account.

## How it works

A launchd user agent (defined in [`launchd.nix`](./launchd.nix)) runs
[`export.sh`](./export.sh) every day at 13:00 local. The script:

1. `op vault list` + `op item list` + `op item get` for every item across every vault
2. JSON-dumps each item (with secrets) into a staging directory
3. `tar | zstd | age`-encrypts → `~/Library/Application Support/onepassword-export/`
4. rsync to `synology:/volume1/homes/chris/backups/onepassword-export/`
5. rsync over Tailscale to `synology-2:/volume1/homes/chris/backups/onepassword-export/`
6. Local retention: 30 days (1P data changes slowly; long retention is fine)

If 1Password.app is locked when the schedule fires, the script logs and
exits silently — next day's run picks up.

## Logs

```bash
tail -F ~/Library/Logs/onepassword-export.log
```

## Trigger manually

```bash
launchctl kickstart -k gui/$(id -u)/org.nixos.onepassword-export
```

## Restore from a 1P export

The archive contains JSON dumps, not a 1pux file. To restore: decrypt with
the age key, then re-import items into any password manager via its API
or CLI. (You can also just open the JSON files in a text editor and read
the values directly — this is for disaster recovery, not normal operation.)

```bash
op read "op://Personal/Vaultwarden Backup Age Key/credential" > /tmp/key.age
age -d -i /tmp/key.age <archive>.tar.zst.age | zstd -d | tar -xf -
shred -u /tmp/key.age
ls payload/   # one directory per vault, JSON file per item
```
