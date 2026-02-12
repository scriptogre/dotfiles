# sunshine: vast.ai VM instance manager with Sunshine game streaming via Tailscale
# Usage: sunshine [up|down|status|ping|search|ssh|logs|open|help|<OFFER_ID>]

sunshine() {
  # ANSI colors
  local R=$'\033[31m' G=$'\033[32m' Y=$'\033[33m' B=$'\033[34m' C=$'\033[36m' W=$'\033[37m' DIM=$'\033[2m' RST=$'\033[0m'

  # Config directory
  local CONFIG_DIR="$HOME/.config/sunshine"

  # Tailscale auth key
  if [[ ! -f "$CONFIG_DIR/authkey" ]]; then
    echo "Error: Tailscale auth key not found"
    echo "Create one at https://login.tailscale.com/admin/settings/keys"
    echo "Then: mkdir -p $CONFIG_DIR && echo 'YOUR_KEY' > $CONFIG_DIR/authkey"
    return 1
  fi
  local TS_AUTHKEY=$(<"$CONFIG_DIR/authkey")

  # Build pre-authorized clients JSON from ~/.config/sunshine/clients/*.pem
  _sunshine_build_state_json() {
    local devices=""
    if [[ -d "$CONFIG_DIR/clients" ]]; then
      for pem in "$CONFIG_DIR/clients"/*.pem; do
        [[ -f "$pem" ]] || continue
        local name=$(basename "$pem" .pem)
        local cert=$(cat "$pem" | sed 's/$/\\n/' | tr -d '\n')
        local uuid=$(uuidgen)
        [[ -n "$devices" ]] && devices+=","
        devices+="{\"name\":\"$name\",\"cert\":\"$cert\",\"uuid\":\"$uuid\"}"
      done
    fi
    cat << STATEEOF
{
  "username": "sunshine",
  "salt": "$(openssl rand -base64 12)",
  "password": "$(echo -n 'sunshine' | openssl dgst -sha256 | cut -d' ' -f2 | tr '[:lower:]' '[:upper:]')",
  "root": {
    "uniqueid": "$(uuidgen)",
    "named_devices": [$devices]
  }
}
STATEEOF
  }

  # Setup script run via SSH after instance boots
  _sunshine_setup_script() {
    cat << 'SETUPEOF'
#!/bin/bash
set -e
START=$(date +%s)
elapsed() { echo "$(($(date +%s) - START))s"; }

echo "[$(elapsed)] Starting setup..."

echo "user:user" | chpasswd

# Enable auto-login
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/autologin.conf << 'AUTOLOGIN'
[Seat:*]
autologin-user=user
autologin-user-timeout=0
AUTOLOGIN

ufw disable 2>/dev/null || true
pkill -9 sunshine 2>/dev/null || true

if ! command -v tailscale &>/dev/null; then
  echo "[$(elapsed)] Installing Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
fi

echo "[$(elapsed)] Starting Tailscale..."
systemctl enable --now tailscaled
tailscale up --authkey=TS_AUTHKEY_PLACEHOLDER --accept-routes --hostname=sunshine

TS_IP=$(tailscale ip -4 2>/dev/null)
echo "[$(elapsed)] Tailscale IP: $TS_IP"

echo "[$(elapsed)] Configuring Sunshine..."
mkdir -p /home/user/.config/sunshine
cat > /home/user/.config/sunshine/sunshine.conf << 'SUNCONF'
address_family = both
origin_web_ui_allowed = wan
SUNCONF
chown -R user: /home/user/.config/sunshine

echo "[$(elapsed)] Starting Sunshine..."
USER_ID=$(id -u user)
sudo -u user XDG_RUNTIME_DIR=/run/user/$USER_ID systemctl --user enable sunshine >/dev/null 2>&1 || true
sudo -u user XDG_RUNTIME_DIR=/run/user/$USER_ID systemctl --user restart sunshine

# Set resolution in background
(
  for i in {1..30}; do
    sleep 2
    OUTPUT=$(sudo -u user bash -c 'export DISPLAY=:0 && xrandr 2>/dev/null' | grep ' connected' | cut -d' ' -f1)
    if [ -n "$OUTPUT" ]; then
      sudo -u user bash -c "export DISPLAY=:0 && xrandr --output $OUTPUT --mode 1920x1080 2>/dev/null"
      break
    fi
  done
) &

echo "[$(elapsed)] Done! Tailscale IP: $TS_IP"
SETUPEOF
  }

  _sunshine_create() {
    local OFFER_ID="$1"
    echo "Creating instance from offer $OFFER_ID..."
    uvx vastai create instance "$OFFER_ID" \
      --image "docker.io/vastai/kvm:ubuntu_desktop_22.04-2025-11-21" \
      --env '-p 41641:41641/udp -p 47984:47984 -p 47989:47989 -p 47990:47990 -p 48010:48010 -p 48002:48002/udp -p 47998:47998/udp -p 47999:47999/udp -p 48000:48000/udp' \
      --disk 100 \
      --ssh \
      --direct
  }

  _sunshine_wait_ssh() {
    local max_attempts=60
    local attempt=0
    local last_status=""
    echo "Waiting for VM to boot..."
    while (( attempt < max_attempts )); do
      local ssh_host=$(_sunshine_get_field "public_ipaddr")
      local ssh_port=$(_sunshine_get_port "22/tcp")
      local inst_status=$(_sunshine_get_field "actual_status")
      if [[ "$inst_status" != "$last_status" ]]; then
        [[ -n "$last_status" ]] && echo ""
        printf "  %s" "$inst_status"
        last_status="$inst_status"
      fi
      if [[ "$inst_status" == "running" && -n "$ssh_port" ]]; then
        if ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=3 -o BatchMode=yes -p "$ssh_port" "root@$ssh_host" 'exit 0' 2>/dev/null; then
          echo " ✓"
          return 0
        fi
      fi
      printf "."
      sleep 5
      ((attempt++))
    done
    echo ""
    echo "Timeout waiting for SSH"
    return 1
  }

  _sunshine_run_setup() {
    local ssh_host=$(_sunshine_get_field "public_ipaddr")
    local ssh_port=$(_sunshine_get_port "22/tcp")
    if [[ -z "$ssh_port" ]]; then
      echo "Instance not ready"; return 1
    fi
    echo "Running setup on instance..."
    local script=$(_sunshine_setup_script)
    script="${script//TS_AUTHKEY_PLACEHOLDER/$TS_AUTHKEY}"
    ssh -o StrictHostKeyChecking=accept-new -p "$ssh_port" "root@$ssh_host" "$script"

    # Deploy pre-authorized clients
    if [[ -d "$CONFIG_DIR/clients" ]] && ls "$CONFIG_DIR/clients"/*.pem &>/dev/null; then
      echo "Deploying pre-authorized clients..."
      local state_json=$(_sunshine_build_state_json)
      ssh -o StrictHostKeyChecking=accept-new -p "$ssh_port" "root@$ssh_host" "cat > /home/user/.config/sunshine/sunshine_state.json && chown user: /home/user/.config/sunshine/sunshine_state.json" <<< "$state_json"
      # Set correct password hash and restart
      ssh -p "$ssh_port" "root@$ssh_host" '
        sudo -u user sunshine --creds sunshine sunshine 2>/dev/null
        USER_ID=$(id -u user)
        sudo -u user XDG_RUNTIME_DIR=/run/user/$USER_ID systemctl --user restart sunshine
      '
    fi
  }

  _sunshine_clean_json() {
    python3 -c "import sys,json,re;raw=sys.stdin.read();clean=re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f]','',raw);print(json.dumps(json.loads(clean)))" 2>/dev/null || echo '[]'
  }

  _sunshine_get_field() {
    local field="$1"
    uvx vastai show instances --raw 2>/dev/null | _sunshine_clean_json | jq -r "if length > 0 then .[0].${field} // empty else empty end" 2>/dev/null
  }

  _sunshine_get_port() {
    local container_port="$1"
    uvx vastai show instances --raw 2>/dev/null | _sunshine_clean_json | jq -r "if length > 0 then .[0].ports[\"${container_port}\"][0].HostPort // empty else empty end" 2>/dev/null
  }

  _sunshine_has_instance() {
    local id=$(_sunshine_get_field "id")
    [[ -n "$id" ]]
  }

  _sunshine_instances_json() {
    uvx vastai show instances --raw 2>/dev/null | _sunshine_clean_json
  }

  _sunshine_get_tailscale_ip() {
    local ssh_host=$(_sunshine_get_field "public_ipaddr")
    local ssh_port=$(_sunshine_get_port "22/tcp")
    [[ -z "$ssh_port" ]] && return 1
    ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -p "$ssh_port" "root@$ssh_host" \
      'tailscale ip -4 2>/dev/null' 2>/dev/null
  }

  _sunshine_wait_ready() {
    _sunshine_wait_ssh || return 1
    _sunshine_run_setup || return 1
    echo "Waiting for Tailscale..."
    local ts_ip=""
    for i in {1..30}; do
      ts_ip=$(_sunshine_get_tailscale_ip)
      [[ -n "$ts_ip" ]] && break
      printf "."
      sleep 3
    done
    echo ""
    if [[ -n "$ts_ip" ]]; then
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "${G}Ready!${RST} Add host in Moonlight: ${C}${ts_ip}${RST}"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      open -a "Moonlight"
    else
      echo "${Y}Tailscale not ready. Run 'sunshine status' later.${RST}"
    fi
  }

  # Scoring for offer selection
  local JQ_SCORE='
    def loc_tier:
      if .geolocation | test("RO|HU|BG|RS|MD") then 1
      elif .geolocation | test("AT|SK|CZ|PL|UA|HR|SI") then 2
      elif .geolocation | test("DE|NL|DK|SE|IT|CH|BE|FR") then 3
      elif .geolocation | test("GB|ES|PT|NO|FI") then 4
      else 5 end;

    def loc_mult:
      if loc_tier == 1 then 1.0
      elif loc_tier == 2 then 0.9
      elif loc_tier == 3 then 0.8
      elif loc_tier == 4 then 0.5
      else 0.2 end;

    def gpu_perf:
      if .gpu_name | test("5090") then 100
      elif .gpu_name | test("5080") then 80
      elif .gpu_name | test("5070.*Ti") then 60
      elif .gpu_name | test("5070") then 50
      elif .gpu_name | test("4090") then 75
      elif .gpu_name | test("4080.*S|4080S") then 58
      elif .gpu_name | test("4080") then 55
      elif .gpu_name | test("4070.*Ti.*S|4070.*S.*Ti") then 48
      elif .gpu_name | test("4070.*Ti|4070Ti") then 45
      elif .gpu_name | test("4070.*S|4070S") then 42
      elif .gpu_name | test("4070") then 38
      elif .gpu_name | test("3090.*Ti") then 38
      elif .gpu_name | test("3090") then 35
      elif .gpu_name | test("3080.*Ti") then 32
      elif .gpu_name | test("3080") then 30
      elif .gpu_name | test("3070.*Ti") then 26
      elif .gpu_name | test("3070") then 24
      elif .gpu_name | test("7900.*XTX") then 70
      elif .gpu_name | test("7900.*XT|7900XT") then 55
      elif .gpu_name | test("7900.*GRE") then 48
      elif .gpu_name | test("7800.*XT") then 45
      elif .gpu_name | test("7700.*XT") then 38
      elif .gpu_name | test("7600") then 30
      elif .gpu_name | test("6950.*XT") then 45
      elif .gpu_name | test("6900.*XT") then 42
      elif .gpu_name | test("6800.*XT") then 38
      elif .gpu_name | test("6800") then 32
      elif .gpu_name | test("6700.*XT") then 28
      elif .gpu_name | test("A6000") then 50
      elif .gpu_name | test("A5500") then 45
      elif .gpu_name | test("A5000") then 42
      elif .gpu_name | test("A4500") then 38
      elif .gpu_name | test("A4000") then 32
      elif .gpu_name | test("L40S") then 70
      elif .gpu_name | test("L40") then 65
      else 0 end;

    def value_score:
      if .dph_total > 0 and gpu_perf > 0 then
        [(gpu_perf / .dph_total), 500] | min
      else 0 end;

    def net_score:
      if .inet_down >= 800 then 100
      elif .inet_down >= 500 then 80
      elif .inet_down >= 400 then 60
      else 40 end;

    def loc_score:
      if loc_tier == 1 then 100
      elif loc_tier == 2 then 75
      elif loc_tier == 3 then 50
      elif loc_tier == 4 then 25
      else 5 end;

    def total_score:
      ((value_score + net_score + (.reliability * 50)) * loc_mult);
  '

  _sunshine_search_json() {
    uvx vastai search offers \
      'vms_enabled=true disk_space>=100 cpu_ram>=16 inet_down>=400 dph<0.40 reliability>0.9' \
      --raw 2>/dev/null
  }

  _sunshine_format_offers() {
    local offers="$1"
    echo "$offers" | jq -r "$JQ_SCORE"'
      [.[] | select(gpu_perf > 0) | {
        id,
        gpu: .gpu_name,
        loc: (.geolocation | split(",")[0] | if . == "" then "Unknown" else . end),
        price: .dph_total,
        net: .inet_down,
        score: total_score,
        loc_t: loc_tier,
        gpu_p: gpu_perf,
        val: value_score,
        net_s: net_score
      }] | sort_by(-.score) | .[:20][] |
      "\(.id)|\(.gpu)|\(.loc)|\(.price)|\(.net | floor)|\(.score | floor)|\(.loc_t)|\(.gpu_p)|\(.val | floor)|\(.net_s)"
    '
  }

  _sunshine_colorize_line() {
    local id="$1" gpu="$2" loc="$3" price="$4" net="$5" score="$6" loc_t="$7" gpu_p="$8" val="$9" net_s="${10}"
    local loc_c gpu_c val_c net_c
    case "$loc_t" in 1) loc_c="$G" ;; 2|3) loc_c="$Y" ;; *) loc_c="$R" ;; esac
    if (( gpu_p >= 55 )); then gpu_c="$G"; elif (( gpu_p >= 38 )); then gpu_c="$Y"; else gpu_c="$R"; fi
    if (( val >= 300 )); then val_c="$G"; elif (( val >= 150 )); then val_c="$Y"; else val_c="$R"; fi
    if (( net_s >= 80 )); then net_c="$G"; elif (( net_s >= 60 )); then net_c="$Y"; else net_c="$R"; fi
    local price_fmt=$(printf "%.2f" "$price")
    printf "%s|${gpu_c}%-12s${RST}|${loc_c}%-12s${RST}|${val_c}\$%s/hr${RST}|${net_c}%4sMbps${RST}|${DIM}score:%s${RST}" \
      "$id" "$gpu" "$loc" "$price_fmt" "$net" "$score"
  }

  # Handle flags
  case "$1" in
    -h|--help) set -- help ;;
  esac

  case "$1" in
    up)
      echo "Finding best offer..."
      local offers=$(_sunshine_search_json)
      if [[ -z "$offers" || "$offers" == "[]" ]]; then
        echo "${R}No offers found${RST}"; return 1
      fi
      local best=$(echo "$offers" | jq -r "$JQ_SCORE"'
        [.[] | select(gpu_perf > 0) | . + {score: total_score}] | sort_by(-.score) | .[0] |
        "\(.id)|\(.gpu_name)|\(.geolocation | split(",")[0])|\(.dph_total)|\(.score | floor)"
      ')
      if [[ -z "$best" || "$best" == "null" ]]; then
        echo "${R}No suitable offers found${RST}"; return 1
      fi
      IFS='|' read -r id gpu loc price score <<< "$best"
      local price_fmt=$(printf "%.2f" "$price")
      echo "Best: ${C}$gpu${RST} in ${G}$loc${RST} @ ${Y}\$${price_fmt}/hr${RST} (score: $score)"
      echo -n "Create instance? [y/N] "
      read -r confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        _sunshine_create "$id" || { echo "${R}Failed${RST}"; return 1; }
        _sunshine_wait_ready
      else
        echo "Cancelled"
      fi
      ;;

    down)
      if ! _sunshine_has_instance; then
        echo "No active instances"; return 0
      fi
      echo "Active instances:"
      _sunshine_instances_json | jq -r '.[] | "  ID:\(.id) | \(.gpu_name) | \(.actual_status) | $\(.dph_total)/hr"' 2>/dev/null
      echo -n "Destroy all? [y/N] "
      read -r confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        _sunshine_instances_json | jq -r '.[].id' 2>/dev/null | while read id; do
          echo "Destroying $id..."
          uvx vastai destroy instance "$id"
        done
        echo "${G}Done${RST}"
      else
        echo "Cancelled"
      fi
      ;;

    status)
      local json=$(_sunshine_instances_json)
      if [[ -z "$json" || "$json" == "[]" ]]; then
        echo "No active instances"; return 0
      fi
      local info=$(jq -r '.[0] | "\(.gpu_name)|\(.actual_status)|\(.dph_total)|\(.start_date)"' <<< "$json")
      IFS='|' read -r gpu state dph start <<< "$info"

      local now=$(date +%s)
      local hours=$(printf "%.2f" $(echo "($now - $start) / 3600" | bc -l))
      local cost=$(printf "%.2f" $(echo "$hours * $dph" | bc -l))
      local rate=$(printf "%.2f" "$dph")

      echo "${C}$gpu${RST} | $state | ${Y}\$${cost}${RST} (${hours}h @ \$${rate}/hr)"

      if [[ "$state" == "running" ]]; then
        local ts_ip=$(_sunshine_get_tailscale_ip)
        if [[ -n "$ts_ip" ]]; then
          echo "Moonlight: ${C}sunshine${RST}"
        else
          echo "${Y}Tailscale not ready${RST}"
        fi
      fi
      ;;

    ssh)
      if ! _sunshine_has_instance; then
        echo "No active instance"; return 1
      fi
      local ssh_host=$(_sunshine_get_field "public_ipaddr")
      local ssh_port=$(_sunshine_get_port "22/tcp")
      if [[ -z "$ssh_host" || -z "$ssh_port" ]]; then
        echo "Instance not ready yet"; return 1
      fi
      echo "Connecting to ${C}$ssh_host:$ssh_port${RST}..."
      ssh -o StrictHostKeyChecking=accept-new -p "$ssh_port" "root@$ssh_host"
      ;;

    logs)
      if ! _sunshine_has_instance; then
        echo "No active instance"; return 1
      fi
      local ssh_host=$(_sunshine_get_field "public_ipaddr")
      local ssh_port=$(_sunshine_get_port "22/tcp")
      if [[ -z "$ssh_host" || -z "$ssh_port" ]]; then
        echo "Instance not ready yet"; return 1
      fi
      echo "Fetching logs from ${C}$ssh_host:$ssh_port${RST}..."
      ssh -o StrictHostKeyChecking=accept-new -p "$ssh_port" "root@$ssh_host" '
        echo "=== TAILSCALE ==="
        tailscale status 2>/dev/null || echo "(not running)"
        echo ""
        echo "=== SUNSHINE ==="
        sudo -u user XDG_RUNTIME_DIR=/run/user/$(id -u user) systemctl --user status sunshine 2>/dev/null | head -10
      '
      ;;

    ping)
      if ! _sunshine_has_instance; then
        echo "No active instance"; return 1
      fi
      local ts_ip=$(_sunshine_get_tailscale_ip)
      if [[ -z "$ts_ip" ]]; then
        echo "${Y}Tailscale not ready yet${RST}"; return 1
      fi
      echo "Pinging ${C}$ts_ip${RST} via Tailscale..."
      tailscale ping "$ts_ip"
      ;;

    open)
      if ! _sunshine_has_instance; then
        echo "No active instance"; return 1
      fi
      echo "Opening vast.ai dashboard..."
      open "https://cloud.vast.ai/instances/"

      local ts_ip=$(_sunshine_get_tailscale_ip)
      if [[ -n "$ts_ip" ]]; then
        local url="https://${ts_ip}:47990"
        echo "Opening Sunshine UI: ${C}$url${RST}"
        echo "Credentials: ${Y}sunshine${RST} / ${Y}sunshine${RST}"
        open "$url"
      else
        echo "${Y}Tailscale not ready yet${RST}"
      fi
      ;;

    search)
      echo "Searching..."
      local offers=$(_sunshine_search_json)
      if [[ -z "$offers" || "$offers" == "[]" ]]; then
        echo "${R}No offers found${RST}"; return 1
      fi
      echo "${DIM}GPU          Location      Price      Network   Score${RST}"
      echo "${DIM}────────────────────────────────────────────────────${RST}"
      _sunshine_format_offers "$offers" | while IFS='|' read -r id gpu loc price net score loc_t gpu_p val net_s; do
        _sunshine_colorize_line "$id" "$gpu" "$loc" "$price" "$net" "$score" "$loc_t" "$gpu_p" "$val" "$net_s"
        echo ""
      done
      ;;

    ""|select)
      if ! command -v fzf &>/dev/null; then
        echo "${R}fzf not installed${RST}"; sunshine search; return 1
      fi
      echo "Searching for offers..."
      local offers=$(_sunshine_search_json)
      if [[ -z "$offers" || "$offers" == "[]" ]]; then
        echo "${R}No offers found${RST}"; return 1
      fi
      local fzf_input=""
      while IFS='|' read -r id gpu loc price net score loc_t gpu_p val net_s; do
        local line=$(_sunshine_colorize_line "$id" "$gpu" "$loc" "$price" "$net" "$score" "$loc_t" "$gpu_p" "$val" "$net_s")
        fzf_input+="$line"$'\n'
      done < <(_sunshine_format_offers "$offers")
      local selected=$(echo -n "$fzf_input" | fzf --ansi --height=15 --reverse \
        --header="Select an offer (Enter to create, Esc to cancel)" --header-first --no-info)
      if [[ -z "$selected" ]]; then
        echo "Cancelled"; return 0
      fi
      local selected_id=$(echo "$selected" | cut -d'|' -f1)
      if [[ -n "$selected_id" ]]; then
        echo "Creating instance from offer ${C}$selected_id${RST}..."
        _sunshine_create "$selected_id" || { echo "${R}Failed${RST}"; return 1; }
        _sunshine_wait_ready
      fi
      ;;

    help)
      echo "Usage: sunshine [command]"
      echo ""
      echo "Commands:"
      echo "  ${C}(none)${RST}    Interactive offer selection with fzf"
      echo "  ${C}up${RST}        Auto-select best offer and create"
      echo "  ${C}down${RST}      Destroy all instances"
      echo "  ${C}status${RST}    Show instance details + Tailscale IP"
      echo "  ${C}ping${RST}      Check latency to instance via Tailscale"
      echo "  ${C}search${RST}    List top offers"
      echo "  ${C}ssh${RST}       SSH into running instance"
      echo "  ${C}logs${RST}      Show Tailscale + Sunshine logs"
      echo "  ${C}open${RST}      Open dashboard + Sunshine web UI"
      echo "  ${C}<ID>${RST}      Create instance from specific offer ID"
      echo ""
      echo "Connect Moonlight to the Tailscale IP shown in 'sunshine status'"
      ;;

    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        _sunshine_create "$1" || { echo "${R}Failed${RST}"; return 1; }
        _sunshine_wait_ready
      else
        echo "${R}Unknown command: $1${RST}"
        echo "Run 'sunshine help' for usage"
        return 1
      fi
      ;;
  esac
}
