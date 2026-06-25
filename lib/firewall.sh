# lib/firewall.sh — обёртки над ufw для открытия 80/tcp и 443/tcp.
# Идемпотентно: если правило уже есть — не дублируем.

# fw_open <port/proto> — добавить allow, если нет
fw_open() {
  local spec="$1" label="${2:-port $spec}"
  require_root
  if ! command -v ufw >/dev/null 2>&1; then
    log_warn "ufw not installed — skipping $label"
    log_warn "install with: apt install ufw"
    return 1
  fi
  # ufw status verbose показывает существующие правила
  if ufw status 2>/dev/null | grep -qE "ALLOW\s+IN\s+${spec//\//\\/}"; then
    log_ok "$label already open"
    return 0
  fi
  if ufw allow "$spec" >/dev/null 2>&1; then
    log_ok "opened $label"
  else
    log_err "ufw allow $spec failed"
    return 1
  fi
}

# fw_close <port/proto> — удалить allow, если есть
fw_close() {
  local spec="$1"
  require_root
  if ! command -v ufw >/dev/null 2>&1; then return 0; fi
  if ufw status 2>/dev/null | grep -qE "ALLOW\s+IN\s+${spec//\//\\/}"; then
    ufw delete allow "$spec" >/dev/null 2>&1 && log_ok "closed $spec" || log_warn "could not close $spec"
  fi
}

# fw_open_naive — открыть 80 и 443 (основной сценарий)
fw_open_naive() {
  fw_open "80/tcp"  "80/tcp  (LE HTTP-01)"
  fw_open "443/tcp" "443/tcp (naiveproxy)"
}

# fw_close_naive — закрыть 80 и 443 (для uninstall)
fw_close_naive() {
  fw_close "443/tcp"
  fw_close "80/tcp"
}