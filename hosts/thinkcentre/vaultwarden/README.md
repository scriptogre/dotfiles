# Vaultwarden — self-hosted password vault with bulletproof backups

Reachable at `https://vault.christiantanul.com` (LAN-only via Caddy).

## Backup architecture

Three-layer redundancy, all driven by [`backup.nix`](./backup.nix) and
[`scripts/backup.sh`](./scripts/backup.sh):

| Layer | What | Where | Frequency |
|---|---|---|---|
| **L1** | Encrypted archive | `/var/backups/vaultwarden/` on ThinkCentre | hourly |
| **L2a** | Same archive, mirrored | `/mnt/nas/homes/chris/backups/vaultwarden/` (SMB) | hourly |
| **L2b** | Same archive, mirrored | `synology-2:/volume1/homes/chris/backups/vaultwarden/` (Tailscale) | hourly |
| **L4** | `bw export` encrypted JSON | USB drive in physical safe | monthly, manual |

Each archive is `tar | zstd | age`-encrypted with a public key whose private
half lives only in 1Password. Even if both Synologys are stolen, the
attacker has nothing without the master password (Vaultwarden's own
encryption) AND the age key (our extra layer).

Local retention 7 days; long-tail retention is on the Synologys (snapshots).

[Gatus](https://status.christiantanul.com) monitors backup freshness and
sends an email if it's >25h old or both Synologys failed.

## One-time setup

### 1. Generate the admin token

Generate a strong token, store it raw in 1Password (item: "Vaultwarden Admin"),
and put the Argon2 hash in `.env`:

```
docker run --rm -it vaultwarden/server:1.35.8-alpine /vaultwarden hash
# Paste the strong token (which you also save to 1Password) when prompted.
# Copy the resulting $argon2id$... hash into vaultwarden/.env as ADMIN_TOKEN='...'.
```

### 2. Generate the age keypair for backup encryption

```
age-keygen -o /tmp/backup.age.key
# Public key:  copy the "# public key: ..." line into vaultwarden/backup.age.pub
# Private key: paste the entire /tmp/backup.age.key file into 1Password
#              (item: "Vaultwarden Backup Age Key")
shred -u /tmp/backup.age.key   # never leave it on disk
```

### 3. Migrate legacy docker volume → bind mount (one-time)

If you previously ran with the docker-managed volume:

```
ssh thinkcentre
sudo mkdir -p /var/lib/vaultwarden
docker stop vaultwarden
sudo cp -a /var/lib/docker/volumes/vaultwarden_vaultwarden_data/_data/. /var/lib/vaultwarden/data/
cd ~/Projects/dotfiles/hosts/thinkcentre/vaultwarden && docker compose up -d
# Once you've verified Vaultwarden works against the bind mount, remove the old volume:
docker volume rm vaultwarden_vaultwarden_data
```

### 4. Set up SSH from ThinkCentre to synology-2 for unattended backup

```
ssh thinkcentre
sudo ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N ""    # systemd runs as root
sudo cat /root/.ssh/id_ed25519.pub
# Add that pubkey to synology-2:~/.ssh/authorized_keys (DSM File Station or via ssh)
sudo ssh-keyscan synology-2 >> /root/.ssh/known_hosts
sudo ssh -o BatchMode=yes synology-2 hostname     # should print "synology-2"
```

### 5. Apply the config

```
just rebuild
sudo systemctl start vaultwarden-backup.service
journalctl -u vaultwarden-backup -n 50
```

You should see local + both Synology destinations report `ok`.

## Operations

### Run a restore drill (or a real restore in disaster)

Verify mode (safe — extracts to a temp dir, touches nothing live):

```bash
# On the Mac:
op read "op://Personal/Vaultwarden Backup Age Key/credential" > /tmp/vw-restore.key
scp /tmp/vw-restore.key thinkcentre:/tmp/vw-restore.key

# On the ThinkCentre:
ssh thinkcentre
NEWEST=$(sudo ls -t /var/backups/vaultwarden/*.tar.zst.age | head -1)
sudo /home/chris/Projects/dotfiles/hosts/thinkcentre/vaultwarden/scripts/restore.sh \
    "$NEWEST" /tmp/vw-restore.key
sudo shred -u /tmp/vw-restore.key

# Back on the Mac:
shred -u /tmp/vw-restore.key
```

For a **real** restore (destructive), add `--apply` as the third argument
to `restore.sh`; you'll be prompted to type `RESTORE` to confirm. The
previous live data dir is renamed (not deleted) as a safety net, so you can
always roll back.

### Monthly USB export (run on the Mac)

```
~/Projects/dotfiles/hosts/thinkcentre/vaultwarden/scripts/export-to-usb.sh /Volumes/USB/vaultwarden-backups
```

Drops `vaultwarden-export-<timestamp>.encrypted.json` onto the USB. Decrypt
later by importing back into any Bitwarden client with your master password.

### Trigger a backup manually

```
ssh thinkcentre 'sudo systemctl start vaultwarden-backup.service ; journalctl -u vaultwarden-backup -n 30'
```

## Failure modes → action

| Symptom | Likely cause | Action |
|---|---|---|
| Gatus alert: "stale (>25h)" | timer not firing | `systemctl status vaultwarden-backup.timer` |
| Gatus alert: "local=*" | container down or `vaultwarden backup` failed | `docker logs vaultwarden`; check `/var/lib/vaultwarden/data` perms |
| Gatus alert: "both-synologys-failed" | Tailscale broken AND SMB mount lost | `tailscale status`, `mountpoint /mnt/nas/homes` |
| Backup runs but archive is tiny | container produced empty snapshot | check `journalctl -u vaultwarden-backup` |
| `ssh synology-2` fails from systemd | host key not in `/root/.ssh/known_hosts` | re-run `ssh-keyscan` step from setup |
