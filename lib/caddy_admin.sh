# lib/caddy_admin.sh — управление caddy через systemd + admin socket.
#
# Стратегия:
#   caddy_reload_safe — основная операция, вызывается после каждой мутации.
#     1) caddy_render (re-render caddy.json из users.json + naive.conf)
#     2) caddy_validate (если caddy в PATH)
#     3) caddy reload через admin socket (zero-downtime)
#     4) если validate/reload упал — откат на .bak + systemctl restart
#
#   caddy_restart — полный рестарт (нужен после смены TLS, например).

# Путь к admin socket
NAIVE_ADMIN_SOCK="${NAIVE_ADMIN_SOCK:-/var/run/caddy/admin.sock}"

# caddy_reload_safe: перерендерить, провалидировать, мягко перезагрузить.
# Возвращает 0 при успехе, 1 при отказе с rollback.
# Оборачивается в with_lock — параллельные reload не должны гонять caddy.json
# (например, юзер дважды Enter жмёт быстро, или внешний скрипт зовёт naive).
caddy_reload_safe() {
  with_lock _caddy_reload_unsafe
}

_caddy_reload_unsafe() {
  # 1) рендер
  if ! caddy_render; then
    log_err "render failed — aborting reload"
    return 1
  fi

  # 2) если caddy установлен — валидируем
  if command -v caddy >/dev/null 2>&1; then
    if ! caddy_validate; then
      log_err "validate failed — rolling back"
      _caddy_rollback
      return 1
    fi
  else
    log_info "caddy not in PATH, skipping validate"
  fi

  # 3) reload или restart в зависимости от доступности caddy
  if systemctl is-active --quiet naive-caddy 2>/dev/null; then
    if command -v caddy >/dev/null 2>&1; then
      if caddy reload --config "$NAIVE_CADDY_JSON" --address "unix//$NAIVE_ADMIN_SOCK" 2>&1; then
        log_ok "caddy reloaded"
        return 0
      else
        log_warn "caddy reload failed — restarting via systemd"
      fi
    fi
    systemctl restart naive-caddy && log_ok "caddy restarted via systemd" || {
      log_err "systemctl restart failed"
      return 1
    }
  else
    log_info "naive-caddy not running — skipping live reload"
    log_info "to apply: systemctl restart naive-caddy"
  fi
  return 0
}

# _caddy_rollback: восстановить caddy.json.bak → caddy.json + рестарт
_caddy_rollback() {
  if [[ -f "$NAIVE_CADDY_BAK" ]]; then
    cp -f "$NAIVE_CADDY_BAK" "$NAIVE_CADDY_JSON"
    log_warn "restored caddy.json from backup"
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart naive-caddy 2>/dev/null || true
  fi
}

# caddy_restart: полный рестарт через systemd (после смены TLS и т.п.)
caddy_restart() {
  if ! command -v systemctl >/dev/null 2>&1; then
    log_err "systemctl not available"
    return 1
  fi
  log_step "Restarting naive-caddy..."
  if systemctl restart naive-caddy; then
    sleep 1
    if systemctl is-active --quiet naive-caddy; then
      log_ok "naive-caddy is active"
      return 0
    else
      log_err "naive-caddy exited after restart"
      systemctl status naive-caddy --no-pager | head -20 >&2 || true
      return 1
    fi
  else
    log_err "systemctl restart failed"
    return 1
  fi
}

# caddy_status: показать статус сервиса (systemd)
caddy_status() {
  if ! command -v systemctl >/dev/null 2>&1; then
    log_warn "systemctl not available on this system"
    return 1
  fi
  systemctl status naive-caddy --no-pager 2>&1 || true
}

# cmd_log access|service — хвосты логов
cmd_log() {
  local kind="${1:-access}"
  case "$kind" in
    access)
      log_file="$NAIVE_LOG_DIR/access.log"
      [[ -f "$log_file" ]] || { log_err "no access log at $log_file"; return 1; }
      log_step "Tailing $log_file (Ctrl-C to exit)"
      tail -n 50 -F "$log_file"
      ;;
    service)
      if command -v journalctl >/dev/null 2>&1; then
        log_step "Tailing journalctl -u naive-caddy (Ctrl-C to exit)"
        journalctl -u naive-caddy -n 100 -f --no-pager
      else
        log_err "journalctl not available"
        return 1
      fi
      ;;
    *)
      die "unknown log kind: $kind (use: access|service)"
      ;;
  esac
}