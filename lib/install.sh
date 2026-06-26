# lib/install.sh — интерактивный первоначальный сетап: TLS, юзер, маскарад, caddy.
#
# Вызывается из `naive install`. Все остальные lib/ уже подгружены.

lib_install_main() {
  require_root
  ensure_dirs

  banner "Naive-Panel — first-time setup"

  # 1) TLS mode: только domain (по решению пользователя)
  log_step "TLS mode: domain (LE via acme.sh HTTP-01)"
  domain=$(prompt "Domain (e.g. proxy.example.com)" "$NAIVE_DOMAIN")
  [[ -z "$domain" ]] && die "domain is required"
  # Безопасная валидация: только то что может попасть в sed/JSON/cert
  # (исключаем |, \, ", ', $ и т.п. — иначе подстановка в caddy.json сломается)
  if ! [[ "$domain" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
    die "invalid domain '$domain' (allowed: letters/digits/dots/dashes, no leading or trailing dash)"
  fi
  email=$(prompt "Email for Let's Encrypt" "$NAIVE_EMAIL")
  [[ -z "$email" ]] && die "email is required for LE registration"
  if ! [[ "$email" =~ ^[^[:space:]@\"\'\`\\|$,]+@[^[:space:]@\"\'\`\\|$,]+\.[A-Za-z]{2,}$ ]]; then
    die "invalid email '$email'"
  fi

  NAIVE_MODE="domain"
  NAIVE_DOMAIN="$domain"
  NAIVE_EMAIL="$email"

  # 2) Masquerade
  log_step "Masquerade site (what visitors see on https://$domain)"
  cat <<EOF
  1. default (generic landing)
  2. minimal (one blank page)
  3. blog
  4. docs
  5. custom local dir (you'll provide path)
  6. custom remote URL (reverse-proxy pass-through)
EOF
  prompt_choice 6 || die "aborted"
  case "$CHOICE" in
    1) NAIVE_MASQUERADE_KIND="default" ;;
    2) NAIVE_MASQUERADE_KIND="minimal" ;;
    3) NAIVE_MASQUERADE_KIND="blog" ;;
    4) NAIVE_MASQUERADE_KIND="docs" ;;
    5)
      NAIVE_MASQUERADE_KIND="custom-dir"
      NAIVE_MASQUERADE=$(prompt "Path to local directory" "/var/www/html")
      ;;
    6)
      NAIVE_MASQUERADE_KIND="custom-url"
      NAIVE_MASQUERADE_URL=$(prompt "Remote URL (e.g. https://example.org)" "")
      [[ -z "$NAIVE_MASQUERADE_URL" ]] && die "URL required"
      ;;
  esac

  # 3) Первый пользователь
  log_step "Create the first user"
  first_name=$(prompt "Username" "alice")
  [[ -z "$first_name" ]] && die "username required"
  first_pass=$(prompt_secret "Password (Enter for auto-generated)")
  [[ -z "$first_pass" ]] && first_pass="$(rand_password)"
  [[ "${#first_pass}" -lt 8 ]] && die "password too short (min 8 chars)"

  # 4) Persist naive.conf
  write_conf
  log_ok "saved /etc/naive/naive.conf"

  # 5) Bootstrap caddy (Go + xcaddy + build)
  if ! command -v caddy >/dev/null 2>&1 || [[ ! -x "$NAIVE_BIN" ]]; then
    log_step "Building caddy with forwardproxy@naive"
    bootstrap_all
  else
    log_ok "caddy already at $NAIVE_BIN"
  fi

  # 6) Создать юзера
  users_add "$first_name" "$first_pass" || true  # может существовать при re-install
  # users_add под flock, нужны runtime dirs
  ensure_dirs

  # 7) Firewall
  if command -v ufw >/dev/null 2>&1; then
    log_step "Opening firewall ports (80/tcp, 443/tcp)"
    ufw allow 80/tcp  >/dev/null 2>&1 || true
    ufw allow 443/tcp >/dev/null 2>&1 || true
  fi

  # 8) Render + validate + start
  caddy_render
  caddy_validate || log_warn "caddy validate failed — check before starting service"

  systemctl daemon-reload
  if ! systemctl is-enabled --quiet naive-caddy 2>/dev/null; then
    systemctl enable naive-caddy
  fi
  systemctl restart naive-caddy
  sleep 2
  if systemctl is-active --quiet naive-caddy; then
    log_ok "naive-caddy is running"
  else
    log_err "naive-caddy failed to start — check: journalctl -u naive-caddy -n 50"
  fi

  # 9) Выпуск TLS через acme.sh (HTTP-01)
  log_step "Requesting Let's Encrypt certificate for $domain"
  tls_issue "$domain" "$email"

  # 10) Финал — показать URI первого юзера
  banner "Ready"
  cat <<EOF
  Domain:     https://$domain
  First user: $first_name
  Password:   $first_pass
EOF
  printf "\n  URI:       "
  _sub_show_uri "$first_name" 2>/dev/null || true

  cat <<EOF

  To manage:  sudo $NAIVE_BIN_DIR/naive

  Logs:       tail -f /var/log/naive/access.log
  Service:    systemctl status naive-caddy
EOF
}