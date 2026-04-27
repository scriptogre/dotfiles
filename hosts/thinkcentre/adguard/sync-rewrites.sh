#!/usr/bin/env bash
# Reconcile AdGuard DNS rewrites against common/network/aliases.nix on every
# AdGuard endpoint listed in $ADGUARD_URLS (space-separated).
#
# Strict mode: aliases.nix is the absolute source of truth. Rewrites that
# exist in AdGuard but not in aliases.nix are deleted. To keep a rewrite,
# add it to aliases.nix.
#
# Invoked by systemd (adguard-rewrites-sync.service) every 5 minutes.

set -Eeuo pipefail

: "${ADGUARD_URLS:?must be set (space-separated)}"
: "${ADGUARD_USER:?must be set}"
: "${ADGUARD_PASSWORD:?must be set}"
: "${ALIASES_FILE:?must be set (path to aliases.nix)}"
# Optional: space-separated curl --resolve mappings (host:port:ip ...).
# Used so the script reaches local Caddy directly when the host's resolver
# (router DNS) doesn't honor the AdGuard rewrites for *.christiantanul.com.
CURL_RESOLVES="${CURL_RESOLVES:-}"
resolve_args=()
for r in $CURL_RESOLVES; do resolve_args+=("--resolve" "$r"); done

# Desired set: every host (name → ip) plus every wildcard.
desired=$(nix eval --json --file "$ALIASES_FILE" \
    | jq -r '
        (.hosts | to_entries[] | "\(.key)\t\(.value.ip)"),
        (.wildcards | to_entries[] | "\(.key)\t\(.value)")
      ' | sort)

# Defensive: never wipe out AdGuard if aliases.nix evaluated to nothing.
if [[ -z "$desired" ]]; then
    echo "ERROR: aliases.nix produced no entries; refusing to reconcile (would delete all rewrites)"
    exit 1
fi

sync_one() {
    local url="$1"
    local api="${url%/}/control"
    local auth=(-u "${ADGUARD_USER}:${ADGUARD_PASSWORD}")
    local headers=(-H "Content-Type: application/json")
    local current added=0 removed=0

    current=$(curl -fsSL --max-time 30 "${resolve_args[@]}" "${auth[@]}" "$api/rewrite/list" \
        | jq -r '.[] | "\(.domain)\t\(.answer)"' | sort)

    while IFS=$'\t' read -r domain ip; do
        [[ -z "$domain" ]] && continue
        curl -fsSL --max-time 30 "${resolve_args[@]}" "${auth[@]}" "${headers[@]}" -X POST "$api/rewrite/add" \
            -d "{\"domain\":\"$domain\",\"answer\":\"$ip\"}" >/dev/null
        echo "  + $domain → $ip"
        added=$((added + 1))
    done < <(comm -23 <(echo "$desired") <(echo "$current"))

    while IFS=$'\t' read -r domain ip; do
        [[ -z "$domain" ]] && continue
        curl -fsSL --max-time 30 "${resolve_args[@]}" "${auth[@]}" "${headers[@]}" -X POST "$api/rewrite/delete" \
            -d "{\"domain\":\"$domain\",\"answer\":\"$ip\"}" >/dev/null
        echo "  - $domain → $ip"
        removed=$((removed + 1))
    done < <(comm -13 <(echo "$desired") <(echo "$current"))

    if (( added == 0 && removed == 0 )); then
        echo "$url: in sync ($(echo "$desired" | wc -l) entries)"
    else
        echo "$url: synced (+$added -$removed)"
    fi
}

failed=()
for url in $ADGUARD_URLS; do
    echo "→ $url"
    if ! sync_one "$url"; then
        echo "  FAILED"
        failed+=("$url")
    fi
done

if (( ${#failed[@]} > 0 )); then
    echo "ERROR: failed to sync: ${failed[*]}"
    exit 1
fi
