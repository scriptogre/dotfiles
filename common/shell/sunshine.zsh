# sunshine: vast.ai VM instance manager with Sunshine game streaming
# Usage: sunshine [up|down|status|search|ssh|ip|open|<OFFER_ID>]

sunshine() {
  # ANSI colors
  local R=$'\033[31m' G=$'\033[32m' Y=$'\033[33m' B=$'\033[34m' C=$'\033[36m' W=$'\033[37m' RST=$'\033[0m'

  local ONSTART='#!/bin/bash
ufw disable 2>/dev/null || true
cat > /usr/local/bin/set-resolution.sh << '\''RESEOF'\''
#!/bin/bash
export DISPLAY=:0
export XAUTHORITY=/var/run/sddm/*
sleep 5
xrandr --output $(xrandr | grep " connected" | cut -d" " -f1) --mode 1920x1080 2>/dev/null
RESEOF
chmod +x /usr/local/bin/set-resolution.sh
mkdir -p /home/user/.config/autostart
cat > /home/user/.config/autostart/set-resolution.desktop << AUTOEOF
[Desktop Entry]
Type=Application
Name=Set Resolution
Exec=/usr/local/bin/set-resolution.sh
AUTOEOF
chown -R user:user /home/user/.config
mkdir -p /home/user/.config/sunshine
cat > /home/user/.config/sunshine/sunshine.conf << SUNEOF
address_family = both
origin_web_ui_allowed = wan
SUNEOF
chown -R user:user /home/user/.config/sunshine
sudo -u user XDG_RUNTIME_DIR=/run/user/$(id -u user) systemctl --user enable sunshine >/dev/null 2>&1
sudo -u user XDG_RUNTIME_DIR=/run/user/$(id -u user) systemctl --user start sunshine'

  _sunshine_create() {
    local OFFER_ID="$1"
    local ONSTART_ENCODED=$(echo "$ONSTART" | tr '\n' ';')
    echo "Creating instance from offer $OFFER_ID..."
    uvx vastai create instance "$OFFER_ID" \
      --image "docker.io/vastai/kvm:ubuntu_desktop_22.04-2025-11-21" \
      --env '-p 1111:1111 -p 3478:3478/udp -p 5900:5900 -p 6100:6100 -p 6200:6200 -p 47984:47984 -p 47989:47989 -p 47990:47990 -p 48010:48010 -p 48002:48002/udp -p 47998:47998/udp -p 47999:47999/udp -p 48000:48000/udp -e OPEN_BUTTON_TOKEN=1 -e OPEN_BUTTON_PORT=1111 -e PORTAL_CONFIG="localhost:1111:11111:/:Instance Portal|localhost:6100:16100:/:Selkies Low Latency Desktop|localhost:6200:16200:/:Apache Guacamole Desktop (VNC)"' \
      --onstart-cmd "$ONSTART_ENCODED" \
      --disk 100 \
      --ssh \
      --direct
  }

  _sunshine_get_field() {
    # Get a specific field from the first instance, sanitizing control characters
    local field="$1"
    uvx vastai show instances --raw 2>/dev/null | perl -pe 's/[\x00-\x08\x0b\x0c\x0e-\x1f]//g' | jq -r "if length > 0 then .[0].${field} // empty else empty end" 2>/dev/null
  }

  _sunshine_has_instance() {
    local id=$(_sunshine_get_field "id")
    [[ -n "$id" ]]
  }

  _sunshine_instances_json() {
    # Get sanitized instances JSON for commands that need the full list
    uvx vastai show instances --raw 2>/dev/null | perl -pe 's/[\x00-\x08\x0b\x0c\x0e-\x1f]//g'
  }

  # jq scoring functions (reused across commands)
  local JQ_SCORE_FUNCS='
    def loc_score:
      if .geolocation | test("HU|RO|BG") then 100
      elif .geolocation | test("AT|SK|CZ|PL") then 80
      elif .geolocation | test("DE|NL|DK|SE") then 60
      elif .geolocation | test("GB|FR|BE") then 40
      else 0 end;
    def gpu_score:
      if .gpu_name | test("5090") then 100
      elif .gpu_name | test("5080") then 95
      elif .gpu_name | test("4090") then 90
      elif .gpu_name | test("5070.*Ti|5070S") then 85
      elif .gpu_name | test("4080.*S|4080S") then 82
      elif .gpu_name | test("4080") then 78
      elif .gpu_name | test("5070") then 75
      elif .gpu_name | test("4070.*S.*Ti|4070S.*Ti") then 70
      elif .gpu_name | test("4070.*Ti|4070Ti") then 65
      elif .gpu_name | test("4070.*S|4070S") then 60
      elif .gpu_name | test("4070") then 55
      elif .gpu_name | test("3090") then 45
      elif .gpu_name | test("3080") then 35
      else 0 end;
    def price_score: if .dph_total <= 0.25 then ((0.25 - .dph_total) / 0.25 * 100) else 0 end;
    def net_score: ([.inet_down, 1000] | min) / 10;
    def rel_score: .reliability * 50;
    def total_score: (loc_score * 3) + (gpu_score * 2.5) + (price_score * 2) + net_score + rel_score;
  '

  case "$1" in
    up)
      echo "Finding best offer..."
      local offers=$(uvx vastai search offers \
        'vms_enabled=true disk_space>=100 cpu_ram>=16 inet_down>=400 dph<0.35 reliability>0.9' \
        --raw 2>/dev/null)

      if [[ -z "$offers" || "$offers" == "[]" ]]; then
        echo "No offers found"
        return 1
      fi

      local best=$(echo "$offers" | jq -r "$JQ_SCORE_FUNCS"'
        [.[] | select(gpu_score > 0) | . + {score: total_score}] | sort_by(-.score) | .[0] |
        "\(.id)|\(.gpu_name)|\(.geolocation | split(",")[0])|\(.dph_total)|\(.score)"
      ')

      if [[ -z "$best" || "$best" == "null" ]]; then
        echo "No suitable offers found (need RTX 30/40/50 series)"
        return 1
      fi

      local id=$(echo "$best" | cut -d'|' -f1)
      local gpu=$(echo "$best" | cut -d'|' -f2)
      local loc=$(echo "$best" | cut -d'|' -f3)
      local price=$(echo "$best" | cut -d'|' -f4)
      local score=$(echo "$best" | cut -d'|' -f5 | cut -d'.' -f1)

      echo "Best: ${C}$gpu${RST} in ${G}$loc${RST} @ ${Y}\$${price}/hr${RST} (score: $score)"
      echo -n "Create instance? [y/N] "
      read -r confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        _sunshine_create "$id"
        [[ $? -eq 0 ]] && echo "${G}Instance created${RST}" || { echo "${R}Failed${RST}"; return 1; }
      else
        echo "Cancelled"
      fi
      ;;

    down)
      if ! _sunshine_has_instance; then
        echo "No active instances"
        return 0
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
      if ! _sunshine_has_instance; then
        echo "No active instances"
        return 0
      fi

      _sunshine_instances_json | jq -r '.[] |
        "ID: \(.id)\nGPU: \(.gpu_name)\nStatus: \(.actual_status)\nIP: \(.public_ipaddr // "pending")\nSSH: ssh -p \(.ssh_port // "N/A") root@\(.ssh_host // "N/A")\nRate: $\(.dph_total)/hr\nStarted: \(.start_date | strftime("%Y-%m-%d %H:%M UTC"))\nRunning: \(((now - .start_date) / 3600 * 100 | floor) / 100)h\nCost: $\(((now - .start_date) / 3600 * .dph_total * 100 | floor) / 100)"
      ' 2>/dev/null
      ;;

    ssh)
      if ! _sunshine_has_instance; then
        echo "No active instance"
        return 1
      fi

      local ssh_host=$(_sunshine_get_field "ssh_host")
      local ssh_port=$(_sunshine_get_field "ssh_port")

      if [[ -z "$ssh_host" || -z "$ssh_port" ]]; then
        echo "Instance not ready yet (no SSH info)"
        return 1
      fi

      echo "Connecting to ${C}$ssh_host:$ssh_port${RST}..."
      ssh -p "$ssh_port" "root@$ssh_host"
      ;;

    ip)
      if ! _sunshine_has_instance; then
        echo "No active instance"
        return 1
      fi

      local ip=$(_sunshine_get_field "public_ipaddr")
      if [[ -z "$ip" ]]; then
        echo "Instance not ready yet (no IP)"
        return 1
      fi

      echo "$ip"
      ;;

    open)
      if ! _sunshine_has_instance; then
        echo "No active instance"
        return 1
      fi

      local ip=$(_sunshine_get_field "public_ipaddr")
      if [[ -z "$ip" ]]; then
        local status=$(_sunshine_get_field "actual_status")
        echo "Instance loading (status: ${Y}${status:-unknown}${RST})"
        echo "Opening vast.ai dashboard..."
        open "https://cloud.vast.ai/instances/"
        return 0
      fi

      local url="https://${ip}:47990"
      echo "Opening ${C}$url${RST}"
      open "$url"
      ;;

    search)
      echo "Searching..."
      local offers=$(uvx vastai search offers \
        'vms_enabled=true disk_space>=100 cpu_ram>=16 inet_down>=400 dph<0.35 reliability>0.9' \
        --raw 2>/dev/null)

      if [[ -z "$offers" || "$offers" == "[]" ]]; then
        echo "No offers found"
        return 1
      fi

      # Color-coded output with individual metric scoring
      echo "$offers" | jq -r "$JQ_SCORE_FUNCS"'
        [.[] | select(gpu_score > 0) | {
          id,
          gpu_name,
          geolocation: (.geolocation | split(",")[0]),
          dph: .dph_total,
          inet: .inet_down,
          score: total_score,
          loc_s: loc_score,
          gpu_s: gpu_score,
          price_s: price_score,
          net_s: net_score
        }] | sort_by(-.score) | .[:10][] |
        "\(.score | floor)|\(.gpu_name)|\(.geolocation)|\(.dph)|\(.inet | floor)|\(.id)|\(.loc_s)|\(.gpu_s)|\(.price_s | floor)|\(.net_s | floor)"
      ' | while IFS='|' read score gpu loc dph inet id loc_s gpu_s price_s net_s; do
        # Color for location
        if (( loc_s >= 80 )); then loc_c="$G"
        elif (( loc_s >= 40 )); then loc_c="$Y"
        else loc_c="$R"; fi

        # Color for GPU
        if (( gpu_s >= 75 )); then gpu_c="$G"
        elif (( gpu_s >= 50 )); then gpu_c="$Y"
        else gpu_c="$R"; fi

        # Color for price (lower = better)
        if (( price_s >= 60 )); then price_c="$G"
        elif (( price_s >= 30 )); then price_c="$Y"
        else price_c="$R"; fi

        # Color for network
        if (( net_s >= 80 )); then net_c="$G"
        elif (( net_s >= 50 )); then net_c="$Y"
        else net_c="$R"; fi

        # Format price
        price_fmt=$(printf "%.2f" "$dph")

        printf "${W}%3s pts${RST} | ${gpu_c}%-12s${RST} | ${loc_c}%-10s${RST} | ${price_c}\$%s/hr${RST} | ${net_c}%4sMbps${RST} | ID:%s\n" \
          "$score" "$gpu" "$loc" "$price_fmt" "$inet" "$id"
      done
      ;;

    "")
      echo "Usage: sunshine <command>"
      echo "  ${C}up${RST}      - Find best offer and create instance"
      echo "  ${C}down${RST}    - Destroy all instances"
      echo "  ${C}status${RST}  - Show instance details + running cost"
      echo "  ${C}search${RST}  - List top 10 offers (color-coded)"
      echo "  ${C}ssh${RST}     - SSH into running instance"
      echo "  ${C}ip${RST}      - Print instance public IP"
      echo "  ${C}open${RST}    - Open Sunshine web UI in browser"
      echo "  ${C}<ID>${RST}    - Create instance from specific offer ID"
      ;;

    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        _sunshine_create "$1"
        [[ $? -eq 0 ]] && echo "${G}Instance created${RST}" || { echo "${R}Failed${RST}"; return 1; }
      else
        echo "${R}Unknown command: $1${RST}"
        return 1
      fi
      ;;
  esac
}
