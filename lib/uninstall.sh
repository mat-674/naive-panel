# lib/uninstall.sh — полное удаление naive-panel.

cmd_uninstall() {
  require_root
  banner "Uninstall naive-panel"
  log_warn "This will stop naive-caddy, remove systemd unit, caddy, and panel binary"
  prompt_confirm "Are you sure?" N || { log_info "aborted"; return 0; }

  # 1) Сервис
  if systemctl list-unit-files naive-caddy.service >/dev/null 2>&1; then
    log_step "Stopping and disabling naive-caddy"
    systemctl stop    naive-caddy 2>/dev/null || true
    systemctl disable naive-caddy 2>/dev/null || true
    rm -f /etc/systemd/system/naive-caddy.service
    systemctl daemon-reload
  fi

  # 2) Бинарь caddy
  if [[ -f "$NAIVE_BIN" ]]; then
    log_step "Removing caddy binary"
    rm -f "$NAIVE_BIN" "$NAIVE_BIN_DIR/xcaddy"
  fi

  # 3) Сам panel
  if [[ -f "$NAIVE_BIN_DIR/naive" ]]; then
    log_step "Removing naive panel binary"
    rm -f "$NAIVE_BIN_DIR/naive"
  fi

  # 4) acme.sh
  if [[ -d "$NAIVE_ACME_DIR" ]] && prompt_confirm "Also remove acme.sh ($NAIVE_ACME_DIR)?" N; then
    log_step "Removing acme.sh"
    rm -rf "$NAIVE_ACME_DIR"
  fi

  # 5) /etc/naive
  if [[ -d "$NAIVE_DATA_DIR" ]]; then
    if prompt_confirm "Keep /etc/naive (users, traffic, masquerade, certs)? [y/N]" N; then
      log_info "keeping $NAIVE_DATA_DIR"
    else
      log_step "Removing $NAIVE_DATA_DIR"
      rm -rf "$NAIVE_DATA_DIR"
    fi
  fi

  # 6) Логи
  if [[ -d "$NAIVE_LOG_DIR" ]] && prompt_confirm "Remove logs at $NAIVE_LOG_DIR?" N; then
    rm -rf "$NAIVE_LOG_DIR"
  fi

  # 7) logrotate
  rm -f /etc/logrotate.d/naive

  # 8) Firewall
  if command -v ufw >/dev/null 2>&1; then
    if prompt_confirm "Remove firewall rules for 80 and 443?" N; then
      fw_close_naive
    fi
  fi

  # 9) Repo clone
  if [[ -d "$NAIVE_PANEL_DIR" ]] && prompt_confirm "Remove panel source at $NAIVE_PANEL_DIR?" N; then
    rm -rf "$NAIVE_PANEL_DIR"
  fi

  cat <<EOF

================================================================
 Uninstalled.

 Remaining files (if any):
EOF
  [[ -d "$NAIVE_DATA_DIR" ]] && echo "  - $NAIVE_DATA_DIR"
  [[ -d "$NAIVE_LOG_DIR"  ]] && echo "  - $NAIVE_LOG_DIR"
  [[ -d "$NAIVE_PANEL_DIR" ]] && echo "  - $NAIVE_PANEL_DIR"
  [[ -d "$NAIVE_ACME_DIR"  ]] && echo "  - $NAIVE_ACME_DIR"
  echo "================================================================"
}