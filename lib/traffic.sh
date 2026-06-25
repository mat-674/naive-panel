# lib/traffic.sh — обёртка вокруг vnstat. Считает трафик всего сервера
# по сетевым интерфейсам. НЕ считает per-user — это технически невозможно
# (CONNECT-туннель непрозрачен для caddy).
#
# Подменю: summary / daily / hourly / live / json.
# vnstat проверяется в traffic_menu при заходе, чтобы модуль можно было
# source'ить без vnstat (например в CI).

# Определить основной интерфейс (по умолчанию eth0 или тот, что в vnstat)
detect_interface() {
  vnstat --iflist 2>/dev/null | head -1 | tr -d ' '
}

# traffic_summary: основная сводка
traffic_summary() {
  local iface="${1:-$(detect_interface)}"
  log_step "Traffic summary ($iface)"
  vnstat -i "$iface" 2>/dev/null || vnstat
}

traffic_daily() {
  local iface="${1:-$(detect_interface)}"
  vnstat -d -i "$iface"
}

traffic_hourly() {
  local iface="${1:-$(detect_interface)}"
  vnstat -h -i "$iface"
}

traffic_top() {
  local iface="${1:-$(detect_interface)}"
  vnstat -t -i "$iface"
}

traffic_live() {
  local iface="${1:-$(detect_interface)}"
  log_step "Live traffic on $iface (Ctrl-C to exit)"
  vnstat -l -i "$iface"
}

traffic_json() {
  local iface="${1:-$(detect_interface)}"
  vnstat --json -i "$iface" 2>/dev/null || vnstat --json
}

# traffic_menu
traffic_menu() {
  require_cmd vnstat "install with: apt install vnstat"
  local iface
  iface=$(detect_interface)
  while :; do
    banner "Traffic statistics"
    cat <<EOF
  Interface: $iface
  Source: vnstat (whole-server accounting)
EOF
    printf "\n"
    cat <<EOF
  1. Summary
  2. Daily
  3. Hourly
  4. Top days
  5. Live (real-time)
  6. JSON dump
  0. Back
EOF
    printf -- "-------------------------------------------------------------\n"
    prompt_choice 6 || return 0
    case "$CHOICE" in
      1) traffic_summary "$iface" ;;
      2) traffic_daily   "$iface" ;;
      3) traffic_hourly  "$iface" ;;
      4) traffic_top     "$iface" ;;
      5) traffic_live    "$iface" ;;
      6) traffic_json    "$iface" | jq . ;;
      0) return 0 ;;
    esac
    printf "\n"
  done
}