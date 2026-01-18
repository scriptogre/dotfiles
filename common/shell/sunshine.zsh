# sunshine: vast.ai VM instance manager with Sunshine game streaming
# Usage: sunshine [up|down|status|search|ssh|ip|open|<OFFER_ID>]

sunshine() {
  # ANSI colors
  local R=$'\033[31m' G=$'\033[32m' Y=$'\033[33m' B=$'\033[34m' C=$'\033[36m' W=$'\033[37m' DIM=$'\033[2m' RST=$'\033[0m'

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
    local field="$1"
    uvx vastai show instances --raw 2>/dev/null | perl -pe 's/[\x00-\x08\x0b\x0c\x0e-\x1f]//g' | jq -r "if length > 0 then .[0].${field} // empty else empty end" 2>/dev/null
  }

  _sunshine_has_instance() {
    local id=$(_sunshine_get_field "id")
    [[ -n "$id" ]]
  }

  _sunshine_instances_json() {
    uvx vastai show instances --raw 2>/dev/null | perl -pe 's/[\x00-\x08\x0b\x0c\x0e-\x1f]//g'
  }

  # Improved scoring with value-based GPU rating and location tiers
  # Location is a MULTIPLIER so non-EU can never beat EU unless dramatically better
  local JQ_SCORE='
    # Location tiers based on latency from Timisoara, Romania
    def loc_tier:
      if .geolocation | test("RO|HU|BG|RS|MD") then 1
      elif .geolocation | test("AT|SK|CZ|PL|UA|HR|SI") then 2
      elif .geolocation | test("DE|NL|DK|SE|IT|CH|BE|FR") then 3
      elif .geolocation | test("GB|ES|PT|NO|FI") then 4
      else 5 end;

    # Location multiplier (non-EU gets heavily penalized)
    def loc_mult:
      if loc_tier == 1 then 1.0
      elif loc_tier == 2 then 0.9
      elif loc_tier == 3 then 0.8
      elif loc_tier == 4 then 0.5
      else 0.2 end;

    # GPU performance tier (relative gaming perf, includes AMD + pro cards)
    def gpu_perf:
      # NVIDIA RTX 50 series
      if .gpu_name | test("5090") then 100
      elif .gpu_name | test("5080") then 80
      elif .gpu_name | test("5070.*Ti") then 60
      elif .gpu_name | test("5070") then 50
      # NVIDIA RTX 40 series
      elif .gpu_name | test("4090") then 75
      elif .gpu_name | test("4080.*S|4080S") then 58
      elif .gpu_name | test("4080") then 55
      elif .gpu_name | test("4070.*Ti.*S|4070.*S.*Ti") then 48
      elif .gpu_name | test("4070.*Ti|4070Ti") then 45
      elif .gpu_name | test("4070.*S|4070S") then 42
      elif .gpu_name | test("4070") then 38
      # NVIDIA RTX 30 series
      elif .gpu_name | test("3090.*Ti") then 38
      elif .gpu_name | test("3090") then 35
      elif .gpu_name | test("3080.*Ti") then 32
      elif .gpu_name | test("3080") then 30
      elif .gpu_name | test("3070.*Ti") then 26
      elif .gpu_name | test("3070") then 24
      # AMD RX 7000 series
      elif .gpu_name | test("7900.*XTX") then 70
      elif .gpu_name | test("7900.*XT|7900XT") then 55
      elif .gpu_name | test("7900.*GRE") then 48
      elif .gpu_name | test("7800.*XT") then 45
      elif .gpu_name | test("7700.*XT") then 38
      elif .gpu_name | test("7600") then 30
      # AMD RX 6000 series
      elif .gpu_name | test("6950.*XT") then 45
      elif .gpu_name | test("6900.*XT") then 42
      elif .gpu_name | test("6800.*XT") then 38
      elif .gpu_name | test("6800") then 32
      elif .gpu_name | test("6700.*XT") then 28
      # NVIDIA Pro (RTX A-series with NVENC)
      elif .gpu_name | test("A6000") then 50
      elif .gpu_name | test("A5500") then 45
      elif .gpu_name | test("A5000") then 42
      elif .gpu_name | test("A4500") then 38
      elif .gpu_name | test("A4000") then 32
      elif .gpu_name | test("L40S") then 70
      elif .gpu_name | test("L40") then 65
      else 0 end;

    # Value score: performance per dollar, capped to prevent extreme outliers
    def value_score:
      if .dph_total > 0 and gpu_perf > 0 then
        [(gpu_perf / .dph_total), 500] | min
      else 0 end;

    # Network score with diminishing returns
    def net_score:
      if .inet_down >= 800 then 100
      elif .inet_down >= 500 then 80
      elif .inet_down >= 400 then 60
      else 40 end;

    # Location score for display (not used in total)
    def loc_score:
      if loc_tier == 1 then 100
      elif loc_tier == 2 then 75
      elif loc_tier == 3 then 50
      elif loc_tier == 4 then 25
      else 5 end;

    # Combined score: base score * location multiplier
    # Base = value + network + reliability bonus
    # Then multiplied by location (EU stays high, non-EU gets crushed)
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

    # Location color based on tier
    local loc_c
    case "$loc_t" in
      1) loc_c="$G" ;;
      2) loc_c="$Y" ;;
      3) loc_c="$Y" ;;
      *) loc_c="$R" ;;
    esac

    # GPU color based on performance tier
    local gpu_c
    if (( gpu_p >= 55 )); then gpu_c="$G"
    elif (( gpu_p >= 38 )); then gpu_c="$Y"
    else gpu_c="$R"; fi

    # Value color (higher = better deal)
    local val_c
    if (( val >= 300 )); then val_c="$G"
    elif (( val >= 150 )); then val_c="$Y"
    else val_c="$R"; fi

    # Network color
    local net_c
    if (( net_s >= 80 )); then net_c="$G"
    elif (( net_s >= 60 )); then net_c="$Y"
    else net_c="$R"; fi

    local price_fmt=$(printf "%.2f" "$price")

    printf "%s|${gpu_c}%-12s${RST}|${loc_c}%-12s${RST}|${val_c}\$%s/hr${RST}|${net_c}%4sMbps${RST}|${DIM}score:%s${RST}" \
      "$id" "$gpu" "$loc" "$price_fmt" "$net" "$score"
  }

  case "$1" in
    up)
      # Auto-select best offer
      echo "Finding best offer..."
      local offers=$(_sunshine_search_json)

      if [[ -z "$offers" || "$offers" == "[]" ]]; then
        echo "${R}No offers found${RST}"
        return 1
      fi

      local best=$(echo "$offers" | jq -r "$JQ_SCORE"'
        [.[] | select(gpu_perf > 0) | . + {score: total_score}] | sort_by(-.score) | .[0] |
        "\(.id)|\(.gpu_name)|\(.geolocation | split(",")[0])|\(.dph_total)|\(.score | floor)"
      ')

      if [[ -z "$best" || "$best" == "null" ]]; then
        echo "${R}No suitable offers found${RST}"
        return 1
      fi

      IFS='|' read -r id gpu loc price score <<< "$best"
      local price_fmt=$(printf "%.2f" "$price")

      echo "Best: ${C}$gpu${RST} in ${G}$loc${RST} @ ${Y}\$${price_fmt}/hr${RST} (score: $score)"
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

    logs)
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

      echo "Fetching logs from ${C}$ssh_host:$ssh_port${RST}..."
      ssh -p "$ssh_port" "root@$ssh_host" 'echo "=== ON-START SCRIPT LOG ===" && cat /var/log/onstart.log 2>/dev/null || echo "(not found)" && echo "" && echo "=== SUNSHINE SERVICE ===" && (sudo -u user XDG_RUNTIME_DIR=/run/user/$(id -u user) journalctl --user -u sunshine -n 50 --no-pager 2>/dev/null || journalctl -u sunshine -n 50 --no-pager 2>/dev/null || echo "(no systemd logs)") && echo "" && echo "=== SUNSHINE CONFIG ===" && cat /home/user/.config/sunshine/sunshine.conf 2>/dev/null || echo "(not found)" && echo "" && echo "=== SUNSHINE PROCESS ===" && pgrep -a sunshine || echo "(not running)"'
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

      echo "Opening vast.ai dashboard..."
      open "https://cloud.vast.ai/instances/"

      local ip=$(_sunshine_get_field "public_ipaddr")
      if [[ -z "$ip" ]]; then
        local status=$(_sunshine_get_field "actual_status")
        echo "Instance loading (status: ${Y}${status:-unknown}${RST})"
      else
        local url="https://${ip}:47990"
        echo "Opening Sunshine UI: ${C}$url${RST}"
        open "$url"
      fi
      ;;

    search)
      echo "Searching..."
      local offers=$(_sunshine_search_json)

      if [[ -z "$offers" || "$offers" == "[]" ]]; then
        echo "${R}No offers found${RST}"
        return 1
      fi

      echo "${DIM}GPU          Location      Price      Network   Score${RST}"
      echo "${DIM}────────────────────────────────────────────────────${RST}"

      _sunshine_format_offers "$offers" | while IFS='|' read -r id gpu loc price net score loc_t gpu_p val net_s; do
        _sunshine_colorize_line "$id" "$gpu" "$loc" "$price" "$net" "$score" "$loc_t" "$gpu_p" "$val" "$net_s"
        echo ""
      done
      ;;

    ""|select)
      # Interactive mode with fzf
      if ! command -v fzf &>/dev/null; then
        echo "${R}fzf not installed. Add it to your nix packages and run: just switch${RST}"
        echo "Falling back to 'sunshine search'"
        sunshine search
        return 1
      fi

      echo "Searching for offers..."
      local offers=$(_sunshine_search_json)

      if [[ -z "$offers" || "$offers" == "[]" ]]; then
        echo "${R}No offers found${RST}"
        return 1
      fi

      # Build fzf input with colors
      local fzf_input=""
      while IFS='|' read -r id gpu loc price net score loc_t gpu_p val net_s; do
        local line=$(_sunshine_colorize_line "$id" "$gpu" "$loc" "$price" "$net" "$score" "$loc_t" "$gpu_p" "$val" "$net_s")
        fzf_input+="$line"$'\n'
      done < <(_sunshine_format_offers "$offers")

      # Run fzf
      local selected=$(echo -n "$fzf_input" | fzf --ansi --height=15 --reverse \
        --header="Select an offer (Enter to create, Esc to cancel)" \
        --header-first \
        --no-info)

      if [[ -z "$selected" ]]; then
        echo "Cancelled"
        return 0
      fi

      # Extract ID from selection (first field before |)
      local selected_id=$(echo "$selected" | cut -d'|' -f1)

      if [[ -n "$selected_id" ]]; then
        echo "Creating instance from offer ${C}$selected_id${RST}..."
        _sunshine_create "$selected_id"
        [[ $? -eq 0 ]] && echo "${G}Instance created${RST}" || { echo "${R}Failed${RST}"; return 1; }
      fi
      ;;

    help)
      echo "Usage: sunshine [command]"
      echo ""
      echo "Commands:"
      echo "  ${C}(none)${RST}    Interactive offer selection with fzf"
      echo "  ${C}up${RST}        Auto-select best offer and create"
      echo "  ${C}down${RST}      Destroy all instances"
      echo "  ${C}status${RST}    Show instance details + running cost"
      echo "  ${C}search${RST}    List top offers (non-interactive)"
      echo "  ${C}ssh${RST}       SSH into running instance"
      echo "  ${C}logs${RST}      Show on-start script + Sunshine logs"
      echo "  ${C}ip${RST}        Print instance public IP"
      echo "  ${C}open${RST}      Open dashboard + Sunshine web UI"
      echo "  ${C}<ID>${RST}      Create instance from specific offer ID"
      echo ""
      echo "Scoring prioritizes: location (EU) > value (perf/\$) > network > reliability"
      ;;

    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        _sunshine_create "$1"
        [[ $? -eq 0 ]] && echo "${G}Instance created${RST}" || { echo "${R}Failed${RST}"; return 1; }
      else
        echo "${R}Unknown command: $1${RST}"
        echo "Run 'sunshine help' for usage"
        return 1
      fi
      ;;
  esac
}
