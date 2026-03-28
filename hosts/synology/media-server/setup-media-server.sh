#!/bin/bash
set -euo pipefail

# Media Server Bootstrap Script
# Configures Prowlarr, Sonarr, Radarr, and qBittorrent after a fresh docker-compose up.
# Requires: all containers running, .env populated with secrets.
#
# Usage:
#   1. Copy .env.example to .env and fill in secrets
#   2. docker compose up -d
#   3. Wait ~30s for services to initialize
#   4. ./setup-media-server.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---------- Load config from .env ----------
if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
    echo "ERROR: .env not found. Copy .env.example and fill in secrets."
    exit 1
fi
source "$SCRIPT_DIR/.env"

# Hostname used for inter-container communication
HOST="${HOSTNAME:-synology}"

# Service URLs (internal)
PROWLARR="http://localhost:9696"
SONARR="http://localhost:8989"
RADARR="http://localhost:7878"
QBIT="http://localhost:9865"

# ---------- Helpers ----------
api() {
    local method="$1" url="$2" api_key="$3"
    shift 3
    curl -sf -X "$method" "$url" \
        -H "X-Api-Key: $api_key" \
        -H "Content-Type: application/json" \
        "$@"
}

wait_for_service() {
    local name="$1" url="$2" api_key="$3"
    echo -n "Waiting for $name..."
    for i in $(seq 1 30); do
        if api GET "$url/api/v1/health" "$api_key" &>/dev/null || \
           api GET "$url/api/v3/health" "$api_key" &>/dev/null; then
            echo " ready"
            return 0
        fi
        sleep 2
        echo -n "."
    done
    echo " TIMEOUT"
    return 1
}

get_api_key() {
    local config_path="$1"
    grep -oP '<ApiKey>\K[^<]+' "$config_path"
}

# ---------- Get API keys from config.xml ----------
echo "=== Reading API keys ==="
PROWLARR_KEY=$(get_api_key "$SCRIPT_DIR/prowlarr_config/config.xml")
SONARR_KEY=$(get_api_key "$SCRIPT_DIR/sonarr_config/config.xml")
RADARR_KEY=$(get_api_key "$SCRIPT_DIR/radarr_config/config.xml")
echo "  Prowlarr: ${PROWLARR_KEY:0:8}..."
echo "  Sonarr:   ${SONARR_KEY:0:8}..."
echo "  Radarr:   ${RADARR_KEY:0:8}..."

# ---------- Wait for services ----------
wait_for_service "Prowlarr" "$PROWLARR" "$PROWLARR_KEY"
wait_for_service "Sonarr" "$SONARR" "$SONARR_KEY"
wait_for_service "Radarr" "$RADARR" "$RADARR_KEY"

# =============================================
# SONARR
# =============================================
echo ""
echo "=== Configuring Sonarr ==="

# Download client: qBittorrent
existing=$(api GET "$SONARR/api/v3/downloadclient" "$SONARR_KEY" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')
if [[ "$existing" == "0" ]]; then
    echo "  Adding qBittorrent download client..."
    api POST "$SONARR/api/v3/downloadclient" "$SONARR_KEY" -d "{
        \"enable\": true,
        \"protocol\": \"torrent\",
        \"priority\": 1,
        \"removeCompletedDownloads\": true,
        \"removeFailedDownloads\": true,
        \"name\": \"qBittorrent\",
        \"implementation\": \"QBittorrent\",
        \"configContract\": \"QBittorrentSettings\",
        \"fields\": [
            {\"name\": \"host\", \"value\": \"$HOST\"},
            {\"name\": \"port\", \"value\": 9865},
            {\"name\": \"useSsl\", \"value\": false},
            {\"name\": \"username\", \"value\": \"${QBIT_USERNAME}\"},
            {\"name\": \"password\", \"value\": \"${QBIT_PASSWORD}\"},
            {\"name\": \"tvCategory\", \"value\": \"tv_series\"},
            {\"name\": \"recentTvPriority\", \"value\": 0},
            {\"name\": \"olderTvPriority\", \"value\": 0},
            {\"name\": \"initialState\", \"value\": 0},
            {\"name\": \"sequentialOrder\", \"value\": true},
            {\"name\": \"firstAndLast\", \"value\": true},
            {\"name\": \"contentLayout\", \"value\": 0}
        ]
    }" > /dev/null
    echo "  Done"
else
    echo "  qBittorrent already configured (skipping)"
fi

# Root folder
existing=$(api GET "$SONARR/api/v3/rootfolder" "$SONARR_KEY" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')
if [[ "$existing" == "0" ]]; then
    echo "  Adding root folder..."
    api POST "$SONARR/api/v3/rootfolder" "$SONARR_KEY" -d '{"path": "/data/media/tv_series"}' > /dev/null
    echo "  Done"
else
    echo "  Root folder already configured (skipping)"
fi

# Media management
echo "  Updating media management settings..."
api PUT "$SONARR/api/v3/config/mediamanagement/1" "$SONARR_KEY" -d '{
    "autoUnmonitorPreviouslyDownloadedEpisodes": false,
    "recycleBinCleanupDays": 7,
    "downloadPropersAndRepacks": "preferAndUpgrade",
    "createEmptySeriesFolders": false,
    "deleteEmptyFolders": true,
    "fileDate": "none",
    "rescanAfterRefresh": "always",
    "setPermissionsLinux": false,
    "chmodFolder": "755",
    "episodeTitleRequired": "always",
    "skipFreeSpaceCheckWhenImporting": true,
    "minimumFreeSpaceWhenImporting": 100,
    "copyUsingHardlinks": true,
    "importExtraFiles": true,
    "extraFileExtensions": "srt",
    "enableMediaInfo": true,
    "id": 1
}' > /dev/null
echo "  Done"

# =============================================
# RADARR
# =============================================
echo ""
echo "=== Configuring Radarr ==="

# Download client: qBittorrent
existing=$(api GET "$RADARR/api/v3/downloadclient" "$RADARR_KEY" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')
if [[ "$existing" == "0" ]]; then
    echo "  Adding qBittorrent download client..."
    api POST "$RADARR/api/v3/downloadclient" "$RADARR_KEY" -d "{
        \"enable\": true,
        \"protocol\": \"torrent\",
        \"priority\": 1,
        \"removeCompletedDownloads\": true,
        \"removeFailedDownloads\": true,
        \"name\": \"qBittorrent\",
        \"implementation\": \"QBittorrent\",
        \"configContract\": \"QBittorrentSettings\",
        \"fields\": [
            {\"name\": \"host\", \"value\": \"$HOST\"},
            {\"name\": \"port\", \"value\": 9865},
            {\"name\": \"useSsl\", \"value\": false},
            {\"name\": \"username\", \"value\": \"${QBIT_USERNAME}\"},
            {\"name\": \"password\", \"value\": \"${QBIT_PASSWORD}\"},
            {\"name\": \"movieCategory\", \"value\": \"movies\"},
            {\"name\": \"recentMoviePriority\", \"value\": 0},
            {\"name\": \"olderMoviePriority\", \"value\": 0},
            {\"name\": \"initialState\", \"value\": 0},
            {\"name\": \"sequentialOrder\", \"value\": true},
            {\"name\": \"firstAndLast\", \"value\": true},
            {\"name\": \"contentLayout\", \"value\": 0}
        ]
    }" > /dev/null
    echo "  Done"
else
    echo "  qBittorrent already configured (skipping)"
fi

# Root folder
existing=$(api GET "$RADARR/api/v3/rootfolder" "$RADARR_KEY" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')
if [[ "$existing" == "0" ]]; then
    echo "  Adding root folder..."
    api POST "$RADARR/api/v3/rootfolder" "$RADARR_KEY" -d '{"path": "/data/media/movies"}' > /dev/null
    echo "  Done"
else
    echo "  Root folder already configured (skipping)"
fi

# Media management
echo "  Updating media management settings..."
api PUT "$RADARR/api/v3/config/mediamanagement/1" "$RADARR_KEY" -d '{
    "autoUnmonitorPreviouslyDownloadedMovies": false,
    "recycleBinCleanupDays": 7,
    "downloadPropersAndRepacks": "preferAndUpgrade",
    "createEmptyMovieFolders": false,
    "deleteEmptyFolders": true,
    "fileDate": "none",
    "rescanAfterRefresh": "always",
    "autoRenameFolders": false,
    "setPermissionsLinux": false,
    "chmodFolder": "755",
    "skipFreeSpaceCheckWhenImporting": true,
    "minimumFreeSpaceWhenImporting": 100,
    "copyUsingHardlinks": true,
    "importExtraFiles": true,
    "extraFileExtensions": "srt",
    "enableMediaInfo": true,
    "id": 1
}' > /dev/null
echo "  Done"

# =============================================
# PROWLARR
# =============================================
echo ""
echo "=== Configuring Prowlarr ==="

# --- Indexers ---
add_prowlarr_indexer() {
    local name="$1"
    # Check if already exists
    existing=$(api GET "$PROWLARR/api/v1/indexer" "$PROWLARR_KEY" | python3 -c "import sys,json; print(any(i['name']=='$name' for i in json.load(sys.stdin)))")
    if [[ "$existing" == "True" ]]; then
        echo "  $name already exists (skipping)"
        return
    fi

    # Get schema for this indexer
    local payload
    payload=$(api GET "$PROWLARR/api/v1/indexer/schema" "$PROWLARR_KEY" | python3 -c "
import sys, json
schemas = json.load(sys.stdin)
match = [s for s in schemas if s['name'] == '$name']
if not match:
    print('NOT_FOUND')
else:
    m = match[0]
    m['enable'] = True
    m['appProfileId'] = 1
    print(json.dumps(m))
")
    if [[ "$payload" == "NOT_FOUND" ]]; then
        echo "  $name: not found in Prowlarr schemas (skipping)"
        return
    fi

    if api POST "$PROWLARR/api/v1/indexer" "$PROWLARR_KEY" -d "$payload" > /dev/null 2>&1; then
        echo "  $name: added"
    else
        echo "  $name: FAILED (may be blocked by Cloudflare or domain down)"
    fi
}

# FileList.io (private tracker - needs credentials from .env)
existing=$(api GET "$PROWLARR/api/v1/indexer" "$PROWLARR_KEY" | python3 -c "import sys,json; print(any(i['name']=='FileList.io' for i in json.load(sys.stdin)))")
if [[ "$existing" == "False" ]]; then
    echo "  Adding FileList.io..."
    schema=$(api GET "$PROWLARR/api/v1/indexer/schema" "$PROWLARR_KEY" | python3 -c "
import sys, json
schemas = json.load(sys.stdin)
m = [s for s in schemas if s['name'] == 'FileList.io'][0]
m['enable'] = True
m['appProfileId'] = 1
for f in m['fields']:
    if f['name'] == 'username':
        f['value'] = '${FILELIST_USERNAME}'
    elif f['name'] == 'passkey':
        f['value'] = '${FILELIST_PASSKEY}'
    elif f['name'] == 'baseSettings.queryLimit':
        f['value'] = 150
    elif f['name'] == 'baseSettings.limitsUnit':
        f['value'] = 1
print(json.dumps(m))
")
    if api POST "$PROWLARR/api/v1/indexer" "$PROWLARR_KEY" -d "$schema" > /dev/null 2>&1; then
        echo "  FileList.io: added"
    else
        echo "  FileList.io: FAILED"
    fi
else
    echo "  FileList.io already exists (skipping)"
fi

# Public indexers
add_prowlarr_indexer "YTS"
add_prowlarr_indexer "The Pirate Bay"
add_prowlarr_indexer "Knaben"
add_prowlarr_indexer "Internet Archive"
add_prowlarr_indexer "1337x"
add_prowlarr_indexer "EZTV"
add_prowlarr_indexer "LimeTorrents"

# --- App connections (Prowlarr -> Sonarr/Radarr) ---
echo ""
echo "  Configuring app connections..."

existing_apps=$(api GET "$PROWLARR/api/v1/applications" "$PROWLARR_KEY" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))')
if [[ "$existing_apps" == "0" ]]; then
    # Sonarr
    echo "  Adding Sonarr connection..."
    api POST "$PROWLARR/api/v1/applications" "$PROWLARR_KEY" -d "{
        \"syncLevel\": \"fullSync\",
        \"name\": \"Sonarr\",
        \"implementation\": \"Sonarr\",
        \"configContract\": \"SonarrSettings\",
        \"fields\": [
            {\"name\": \"prowlarrUrl\", \"value\": \"http://$HOST:9696\"},
            {\"name\": \"baseUrl\", \"value\": \"http://$HOST:8989\"},
            {\"name\": \"apiKey\", \"value\": \"$SONARR_KEY\"},
            {\"name\": \"syncCategories\", \"value\": [5000,5010,5020,5030,5040,5045,5050,5060,5070,5080]},
            {\"name\": \"animeSyncCategories\", \"value\": [5070]}
        ]
    }" > /dev/null
    echo "  Done"

    # Radarr
    echo "  Adding Radarr connection..."
    api POST "$PROWLARR/api/v1/applications" "$PROWLARR_KEY" -d "{
        \"syncLevel\": \"fullSync\",
        \"name\": \"Radarr\",
        \"implementation\": \"Radarr\",
        \"configContract\": \"RadarrSettings\",
        \"fields\": [
            {\"name\": \"prowlarrUrl\", \"value\": \"http://$HOST:9696\"},
            {\"name\": \"baseUrl\", \"value\": \"http://$HOST:7878\"},
            {\"name\": \"apiKey\", \"value\": \"$RADARR_KEY\"},
            {\"name\": \"syncCategories\", \"value\": [2000,2010,2020,2030,2040,2045,2050,2060,2070,2080,2090]}
        ]
    }" > /dev/null
    echo "  Done"
else
    echo "  App connections already configured (skipping)"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Services:"
echo "  Sonarr:      http://$HOST:8989"
echo "  Radarr:      http://$HOST:7878"
echo "  Prowlarr:    http://$HOST:9696"
echo "  qBittorrent: http://$HOST:9865"
echo ""
echo "Note: Recyclarr handles quality profiles separately (recyclarr_config/)."
echo "Note: Some public indexers may fail if blocked by Cloudflare."
