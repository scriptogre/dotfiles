# RECOVERY — opening your 1Password backups

If your 1Password account is locked out / unrecoverable, this page gets your
data back. Read top to bottom; it's short on purpose.

## What you have

- Encrypted daily exports of your entire 1Password vault on **two Synologys**:
  - Local: `synology` (LAN, `192.168.0.14`) → `~chris/backups/onepassword-export/`
  - Off-site: `synology-2` (Tailscale, `100.114.162.56`) → `~chris/backups/onepassword-export/`
- One copy on the Mac itself: `~/Library/Application Support/onepassword-export/`
- Each archive is `tar.zst` encrypted with `age`. Public key in dotfiles, private key in 1Password (item: "Vaultwarden Backup Age Key", field: `credential`).

## Three recovery scenarios

### A. 1Password works, you just want to read an item

You don't need this procedure — open the 1Password app or go to https://my.1password.com.

### B. 1Password account is locked but you can sign in via web

```bash
# 1. Sign in at https://my.1password.com (use your Secret Key from the Emergency Kit)
# 2. Open "Vaultwarden Backup Age Key" → copy the "credential" field
# 3. On any machine with `age` installed:
echo 'AGE-SECRET-KEY-...paste here...' > /tmp/key.age

# 4. Get the latest backup. Either Synology works:
scp synology-2:backups/onepassword-export/onepassword-LATEST.tar.zst.age /tmp/

# 5. Decrypt + extract:
mkdir /tmp/op-restore
age -d -i /tmp/key.age /tmp/onepassword-LATEST.tar.zst.age | zstd -d | tar -C /tmp/op-restore -xf -

# 6. WIPE THE KEY:
shred -u /tmp/key.age 2>/dev/null || rm -P /tmp/key.age 2>/dev/null || rm -f /tmp/key.age

# 7. Browse:
ls /tmp/op-restore/payload/                  # one dir per vault
jq . /tmp/op-restore/payload/<vault-id>/<item-id>.json    # specific item
ls /tmp/op-restore/payload/<vault-id>/documents/          # uploaded files
```

### C. 1Password is fully unreachable (no app, no web)

You **must** have the age private key stored outside 1Password. You should
have printed it onto paper and kept it with your 1P Emergency Kit.

If you have the printed key:

```bash
echo 'AGE-SECRET-KEY-...transcribed from paper...' > /tmp/key.age
# … then continue from step 4 in scenario B above.
```

If you don't have the printed key: you've lost everything. This is the
exact scenario the printed copy is for. Add this to your TODO right now if
you haven't done it yet.

## Reading individual items

The archive contains one JSON file per item plus document files.

```bash
# Find an item by name:
grep -l "Gmail" /tmp/op-restore/payload/*/*.json

# Pretty-print a single item with its passwords/TOTP/notes:
jq . /tmp/op-restore/payload/<vault-id>/<item-id>.json

# Just the password value:
jq -r '.fields[] | select(.label == "password") | .value' \
    /tmp/op-restore/payload/<vault-id>/<item-id>.json

# Just the TOTP secret (if any):
jq -r '.fields[] | select(.type == "OTP") | .value' \
    /tmp/op-restore/payload/<vault-id>/<item-id>.json
```

## What's NOT in the backup

- **Passkeys** — 1P stores them but they're device-bound; not exportable
- **Item version history** — only the latest state is captured
- **Trash** — deleted items aren't included
- **Manual exports / 1pux files** — different format; we don't capture those

For passkeys you have to recover via the issuing site's account-recovery flow.

## Bulk-restoring into a new password manager

The backups are 1P JSON, not Bitwarden/1pux. To bulk-import elsewhere you
need to convert. Practical approach when you actually need it:

1. Re-create your 1Password account at 1password.com (using the Secret Key
   from your Emergency Kit) and import items via their UI from the JSON dump
2. **Or**: write a small converter (1P JSON → Bitwarden JSON), then
   `bw import bitwardenjson <converted-file>`. Vaultwarden runs at
   `https://vault.christiantanul.com` and is ready to receive.

For emergency single-item lookup (scenarios B and C above), no conversion
is needed — read the JSON directly.

## Verifying your backups work (do this once a quarter)

```bash
# On any machine with `age`, `zstd`, `op`:
op read "op://Personal/Vaultwarden Backup Age Key/credential" > /tmp/key.age
LATEST=$(ssh synology-2 'ls -t backups/onepassword-export/*.tar.zst.age | head -1')
scp "synology-2:$LATEST" /tmp/test.age
mkdir /tmp/test-restore
age -d -i /tmp/key.age /tmp/test.age | zstd -d | tar -C /tmp/test-restore -xf -
ls /tmp/test-restore/payload/      # should see your vault dirs
rm -rf /tmp/test-restore /tmp/test.age
shred -u /tmp/key.age
```

If that succeeds, you can recover. If it fails, fix the reason now while
nothing is at stake.
