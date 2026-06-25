# lib/tls.sh — TLS только domain-режим: acme.sh + Let's Encrypt HTTP-01.
#
# Требует:
#   - 80/tcp свободен (acme.sh standalone поднимает listener на нём)
#   - 80/tcp на сервере указывает прямо на наш IP (не за CF proxy)
#   - домен уже резолвится в A/AAAA на этот сервер
#
# План:
#   - установить acme.sh в /opt/acme.sh (один раз)
#   - зарегистрировать account (CA: LE)
#   - выпустить сертификат для домена (HTTP-01 standalone)
#   - renew: acme.sh --renew --force
#
# Все операции требуют root — проверка внутри каждой entry-функции.

ACME_REPO="https://github.com/acmesh-official/acme.sh.git"

# Установка acme.sh (идемпотентно)
tls_install_acme() {
  require_root
  if [[ -x "$NAIVE_ACME_DIR/acme.sh" ]]; then
    log_ok "acme.sh already installed at $NAIVE_ACME_DIR"
    return 0
  fi
  log_step "Installing acme.sh → $NAIVE_ACME_DIR"
  if ! command -v git >/dev/null 2>&1; then
    apt-get install -y git
  fi
  git clone --depth 1 "$ACME_REPO" "$NAIVE_ACME_DIR"
  # Установка в режиме standalone
  "$NAIVE_ACME_DIR/acme.sh" --install \
    --home "$NAIVE_ACME_DIR" \
    --no-cron \
    --no-profile 2>&1 | tail -5
  log_ok "acme.sh installed"
}

# Регистрация аккаунта (один раз, сохраняется в ~/.acme.sh/account.conf)
tls_register_account() {
  require_root
  local email="$1"
  [[ -n "$email" ]] || die "email required for acme.sh registration"
  if "$NAIVE_ACME_DIR/acme.sh" --list --home "$NAIVE_ACME_DIR" 2>/dev/null | grep -q "ACCOUNT_THUMBPRINT"; then
    log_ok "acme.sh account already registered"
    return 0
  fi
  log_step "Registering Let's Encrypt account for $email"
  "$NAIVE_ACME_DIR/acme.sh" --register-account --accountemail "$email" \
    --home "$NAIVE_ACME_DIR" --server letsencrypt
  log_ok "account registered"
}

# Выпуск сертификата HTTP-01
# tls_issue <domain> <email>
tls_issue() {
  require_root
  local domain="${1:-$NAIVE_DOMAIN}" email="${2:-$NAIVE_EMAIL}"
  [[ -n "$domain" ]] || die "domain required"
  [[ -n "$email" ]]  || die "email required"

  tls_install_acme
  tls_register_account "$email"

  # Если уже есть валидный — пропускаем
  local cert_dir="$NAIVE_ACME_DIR/$domain"
  if [[ -f "$cert_dir/fullchain.cer" ]]; then
    local expires
    expires=$(openssl x509 -enddate -noout -in "$cert_dir/fullchain.cer" 2>/dev/null \
              | cut -d= -f2)
    log_info "existing cert expires: $expires"
    # Если до истечения > 30 дней — пропускаем
    if openssl x509 -checkend 2592000 -noout -in "$cert_dir/fullchain.cer" >/dev/null 2>&1; then
      log_ok "certificate is still valid (>30d), skipping re-issue"
      tls_install_into_caddy "$domain"
      return 0
    fi
  fi

  log_step "Requesting certificate for $domain (HTTP-01 standalone)"

  # Предупреждение про Cloudflare
  log_warn "Domain $domain must resolve directly to this server's IP (not via Cloudflare proxy)"
  log_warn "If using Cloudflare, set DNS record to 'DNS only' (grey cloud) for ACME"

  # Остановить caddy, чтобы освободить 80/tcp
  local was_active=0
  if systemctl is-active --quiet naive-caddy 2>/dev/null; then
    was_active=1
    log_info "stopping naive-caddy to free port 80 for ACME"
    systemctl stop naive-caddy
  fi

  if "$NAIVE_ACME_DIR/acme.sh" --issue \
        -d "$domain" \
        --httpport 80 \
        --home "$NAIVE_ACME_DIR" \
        --server letsencrypt; then
    log_ok "certificate issued"
    tls_install_into_caddy "$domain"
  else
    log_err "acme.sh --issue failed"
    log_err "common causes:"
    log_err "  - domain doesn't point to this server (check: dig +short $domain)"
    log_err "  - port 80 blocked by firewall or ISP"
    log_err "  - Cloudflare proxy enabled (must be grey cloud)"
    [[ $was_active -eq 1 ]] && systemctl start naive-caddy
    return 1
  fi

  # Поднять caddy обратно
  if [[ $was_active -eq 1 ]]; then
    systemctl start naive-caddy
  fi
  return 0
}

# Установить сертификат в место, откуда caddy его подхватит
# (мы используем встроенный ACME в caddy, поэтому просто копируем для бэкапа)
tls_install_into_caddy() {
  local domain="$1"
  local src="$NAIVE_ACME_DIR/$domain"
  local dst="$NAIVE_CA_DIR/live"
  mkdir -p "$dst"
  if [[ -f "$src/fullchain.cer" ]]; then
    cp -f "$src/fullchain.cer" "$dst/$domain.crt"
    cp -f "$src/$domain.key"   "$dst/$domain.key"
    chmod 0644 "$dst/$domain.crt"
    chmod 0600 "$dst/$domain.key"
    log_ok "cert copied to $dst/$domain.crt"
  fi
}

# tls_renew: принудительный renew
tls_renew() {
  require_root
  local domain="${1:-$NAIVE_DOMAIN}"
  [[ -x "$NAIVE_ACME_DIR/acme.sh" ]] || die "acme.sh not installed"
  log_step "Renewing certificate for $domain"

  local was_active=0
  if systemctl is-active --quiet naive-caddy 2>/dev/null; then
    was_active=1
    systemctl stop naive-caddy
  fi
  if "$NAIVE_ACME_DIR/acme.sh" --renew -d "$domain" --force \
       --httpport 80 --home "$NAIVE_ACME_DIR" --server letsencrypt; then
    log_ok "renewed"
    tls_install_into_caddy "$domain"
  else
    log_err "renew failed"
    [[ $was_active -eq 1 ]] && systemctl start naive-caddy
    return 1
  fi
  [[ $was_active -eq 1 ]] && systemctl start naive-caddy
}

# tls_status: показать состояние сертификата
tls_status() {
  local domain="${1:-$NAIVE_DOMAIN}"
  local cert_file="$NAIVE_ACME_DIR/$domain/fullchain.cer"
  if [[ ! -f "$cert_file" ]]; then
    log_warn "no certificate at $cert_file"
    return 1
  fi
  openssl x509 -in "$cert_file" -noout -subject -issuer -dates 2>/dev/null
  local days_left
  days_left=$(( ( $(date -d "$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)" +%s) - $(date +%s) ) / 86400 ))
  printf "days remaining: %d\n" "$days_left"
}

# tls_menu: подменю TLS
tls_menu() {
  while :; do
    banner "TLS / certificates"
    cat <<EOF
  Mode: domain (Let's Encrypt via acme.sh HTTP-01)
  Domain: $NAIVE_DOMAIN
  Email:  $NAIVE_EMAIL
EOF
    printf "\n"
    cat <<EOF
  1. Show certificate status
  2. Issue / renew certificate
  3. Force renew now
  0. Back
EOF
    printf -- "-------------------------------------------------------------\n"
    prompt_choice 3 || return 0
    case "$CHOICE" in
      1) tls_status ;;
      2) tls_issue ;;
      3) tls_renew ;;
      0) return 0 ;;
    esac
    printf "\n"
  done
}