# lib/upgrade.sh — обновление panel и caddy.

# cmd_upgrade self — пересобрать /usr/local/bin/naive из git
cmd_upgrade_self() {
  require_root
  log_step "Updating naive-panel from $NAIVE_PANEL_DIR"

  if [[ ! -d "$NAIVE_PANEL_DIR/.git" ]]; then
    die "$NAIVE_PANEL_DIR is not a git repo — nothing to update"
  fi

  (cd "$NAIVE_PANEL_DIR" && git pull --rebase --autostash) || {
    log_err "git pull failed — resolve manually and re-run"
    return 1
  }

  # Пересборка бинарника через install.sh --self-update
  if [[ -x "$NAIVE_PANEL_DIR/install.sh" ]]; then
    "$NAIVE_PANEL_DIR/install.sh" --self-update
  else
    log_err "$NAIVE_PANEL_DIR/install.sh missing"
    return 1
  fi

  log_ok "panel updated"
}

# cmd_upgrade caddy — пересобрать caddy с актуальной версией forwardproxy@naive
cmd_upgrade_caddy() {
  require_root
  if ! declare -F upgrade_caddy >/dev/null 2>&1; then
    log_err "bootstrap.sh not loaded — caddy upgrade unavailable"
    return 1
  fi
  upgrade_caddy
}

# Диспетчер (вызывается из naive как `dispatch_upgrade`)
dispatch_upgrade() {
  local what="${1:-}"
  case "$what" in
    self|panel) cmd_upgrade_self ;;
    caddy)      cmd_upgrade_caddy ;;
    "")
      cat <<EOF
Usage: naive upgrade (self|caddy)

  self   — git pull + rebuild /usr/local/bin/naive
  caddy  — rebuild /usr/local/bin/caddy with latest forwardproxy@naive
EOF
      ;;
    *) die "unknown upgrade target: $what (use self or caddy)" ;;
  esac
}