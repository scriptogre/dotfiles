# Network aliases — single source of truth

`aliases.nix` is the canonical mapping from hostname → IP for the homelab.
Everything that needs to know "what IP is `synology-2`?" reads this file.

## Consumers

| Consumer | What it produces | When it runs |
|---|---|---|
| [`common/home.nix`](../home.nix) | `~/.ssh/config.d/hosts` on Mac and ThinkCentre — every host with `ssh = { user = "..."; }` becomes an SSH alias | At each home-manager rebuild |
| [`hosts/thinkcentre/flake.nix`](../../hosts/thinkcentre/flake.nix) `networking.hosts` | `/etc/hosts` on the ThinkCentre — covers `ping`/`curl`/etc. by name | At each NixOS rebuild |
| [`hosts/thinkcentre/adguard/sync-rewrites.nix`](../../hosts/thinkcentre/adguard/sync-rewrites.nix) | AdGuard DNS rewrites on **every** AdGuard endpoint (`adguard.christiantanul.com`, `adguard-2.christiantanul.com`) — covers LAN-wide DNS | Every 5 minutes via systemd timer; strict reconciliation |

## Workflow

### Adding a host
1. Edit `common/network/aliases.nix` to add the entry.
2. `just rebuild` on each NixOS host to refresh `/etc/hosts` and (on Mac) the SSH config.
3. AdGuard picks up the new rewrite automatically within 5 minutes. To trigger immediately:
   `ssh thinkcentre 'sudo systemctl start adguard-rewrites-sync.service'`

### Renaming a host
Edit the key in `aliases.nix`. The same propagation rules apply. Old AdGuard
rewrite is deleted, new one added. SSH and `/etc/hosts` regenerate from the
new key on rebuild.

### Removing a host
Delete the entry in `aliases.nix`. AdGuard removes within 5 minutes; SSH
and `/etc/hosts` lose the alias on next rebuild.

## Rules

- **Never edit AdGuard rewrites via the web UI.** They will be deleted on the
  next reconcile cycle. The `sync-rewrites.sh` script is strict-mode by design.
- **Wildcards (`*.example.com`) only apply to AdGuard.** They're skipped by the
  SSH and `/etc/hosts` generators because those formats don't support wildcards.
- **A host without `ssh = { user = "..."; }` is DNS-only.** Useful for things
  like `router` that you don't ssh into.

## On non-NixOS machines (Synologys)

The Synologys aren't Nix-managed, so they can't consume `aliases.nix` directly.
**They don't need to.** Both Synologys use AdGuard for DNS — the primary
(`adguard.christiantanul.com`) on the home LAN, the replica
(`adguard-2.christiantanul.com`) at the off-site. Since AdGuard rewrites are
auto-reconciled from `aliases.nix`, every hostname is resolvable on the
Synologys via DNS automatically.

In practice that means `ssh synology-2` from a Synology just works (assuming
your DSM user matches the target — otherwise specify `chris@synology-2`).
No `~/.ssh/config` editing required.

## Why so many consumers, not just one?

Because each layer covers a different threat model:

- **AdGuard rewrites** cover the whole LAN (browsers, phones, IoT, etc.) but
  fail if AdGuard is down or your machine is on a non-home network.
- **`/etc/hosts`** on the ThinkCentre covers it even if AdGuard is offline.
- **SSH aliases** cover ssh/scp/rsync deterministically regardless of DNS state.

If just one layer fails (AdGuard restart, DNS misconfig, off-LAN), the
others still work — and your password backup script keeps running.
