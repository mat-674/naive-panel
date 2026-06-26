# lib/config.sh — пути и defaults для /etc/naive/naive.conf
# Этот файл — единственное место, где определены все пути рантайма.

# Версия панели (тащится в баннер)
NAIVE_VERSION="0.1.0"
NAIVE_TITLE="Naive-Panel"

# Дефолтные пути (могут быть переопределены в /etc/naive/naive.conf)
NAIVE_DATA_DIR="${NAIVE_DATA_DIR:-/etc/naive}"
NAIVE_LOG_DIR="${NAIVE_LOG_DIR:-/var/log/naive}"
NAIVE_LOCK="${NAIVE_LOCK:-/var/lock/naive.lock}"
NAIVE_BIN="${NAIVE_BIN:-/usr/local/bin/caddy}"
NAIVE_BIN_DIR="${NAIVE_BIN_DIR:-/usr/local/bin}"
NAIVE_PANEL_DIR="${NAIVE_PANEL_DIR:-/opt/naive-panel}"
NAIVE_ACME_DIR="${NAIVE_ACME_DIR:-/opt/acme.sh}"

# Внутри NAIVE_DATA_DIR
NAIVE_CONF="${NAIVE_DATA_DIR}/naive.conf"
NAIVE_USERS="${NAIVE_DATA_DIR}/users.json"
NAIVE_STATE="${NAIVE_DATA_DIR}/state.json"
NAIVE_CA_DIR="${NAIVE_DATA_DIR}/ca"
NAIVE_CA_LIVE="${NAIVE_CA_DIR}/live"
NAIVE_CERT_FILE="${NAIVE_CA_LIVE}/naive.crt"
NAIVE_KEY_FILE="${NAIVE_CA_LIVE}/naive.key"
NAIVE_CADDY_DIR="${NAIVE_DATA_DIR}/caddy"
NAIVE_CADDY_JSON="${NAIVE_CADDY_DIR}/caddy.json"
NAIVE_CADDY_BAK="${NAIVE_CADDY_DIR}/caddy.json.bak"
NAIVE_MASQUERADE="${NAIVE_DATA_DIR}/masquerade"

# Доступные шаблоны маскарада
NAIVE_MASQUERADE_TEMPLATES=(default minimal blog docs)

# Defaults, которые может переопределить пользователь в naive.conf
NAIVE_MODE="${NAIVE_MODE:-domain}"            # domain | ip  (но ip-режим мы выпилили)
NAIVE_DOMAIN="${NAIVE_DOMAIN:-}"
NAIVE_EMAIL="${NAIVE_EMAIL:-}"
NAIVE_BIND_PORT="${NAIVE_BIND_PORT:-443}"
NAIVE_MASQUERADE_KIND="${NAIVE_MASQUERADE_KIND:-default}"  # имя шаблона | custom-dir | custom-url
NAIVE_MASQUERADE_URL="${NAIVE_MASQUERADE_URL:-}"          # для custom-url

# --- load_conf: подгружает /etc/naive/naive.conf, если есть ---
load_conf() {
  [[ -f "$NAIVE_CONF" ]] || return 0
  # shellcheck disable=SC1090
  source "$NAIVE_CONF"
}

# --- ensure_dirs: создаёт рантайм-каталоги с правильными правами ---
ensure_dirs() {
  local d
  for d in "$NAIVE_DATA_DIR" "$NAIVE_CADDY_DIR" "$NAIVE_CA_DIR" \
           "$NAIVE_MASQUERADE" "$NAIVE_LOG_DIR" \
           "$(dirname "$NAIVE_LOCK")"; do
    [[ -d "$d" ]] || mkdir -p "$d"
    chmod 750 "$d" 2>/dev/null || true
  done
  [[ -f "$NAIVE_LOCK" ]] || : > "$NAIVE_LOCK"
  chmod 0644 "$NAIVE_LOCK"
}

# --- write_conf: пишет текущее окружение в naive.conf ---
write_conf() {
  local body
  body=$(cat <<EOF
# Naive-Panel config — generated $(date -u +%FT%TZ)
# DO NOT EDIT unless you know what you are doing.
NAIVE_DATA_DIR="$NAIVE_DATA_DIR"
NAIVE_LOG_DIR="$NAIVE_LOG_DIR"
NAIVE_LOCK="$NAIVE_LOCK"
NAIVE_BIN="$NAIVE_BIN"
NAIVE_BIN_DIR="$NAIVE_BIN_DIR"
NAIVE_PANEL_DIR="$NAIVE_PANEL_DIR"
NAIVE_ACME_DIR="$NAIVE_ACME_DIR"
NAIVE_MODE="$NAIVE_MODE"
NAIVE_DOMAIN="$NAIVE_DOMAIN"
NAIVE_EMAIL="$NAIVE_EMAIL"
NAIVE_BIND_PORT="$NAIVE_BIND_PORT"
NAIVE_MASQUERADE_KIND="$NAIVE_MASQUERADE_KIND"
NAIVE_MASQUERADE_URL="$NAIVE_MASQUERADE_URL"
EOF
)
  atomic_write "$NAIVE_CONF" "$body" 0600
}

# --- status_summary: одна строка про текущее состояние для шапки меню ---
status_summary() {
  local mode="$NAIVE_MODE" host
  if [[ "$mode" == "domain" && -n "$NAIVE_DOMAIN" ]]; then
    host="$NAIVE_DOMAIN"
  else
    host="$(hostname -f 2>/dev/null || hostname)"
  fi
  printf "server: %s  mode: %s  port: %s" "$host" "$mode" "$NAIVE_BIND_PORT"
}

# --- самозагрузка при импорте ---
load_conf

# Если NAIVE_TEST_MODE=1 — перенаправляем все пути во временный каталог
# для герметичных тестов. Должно вызываться РАНЬШЕ ensure_dirs.
if [[ "${NAIVE_TEST_MODE:-0}" == "1" ]]; then
  NAIVE_DATA_DIR="${NAIVE_TEST_DIR:-/tmp/naive-test}/etc"
  NAIVE_LOG_DIR="${NAIVE_TEST_DIR:-/tmp/naive-test}/log"
  NAIVE_LOCK="${NAIVE_TEST_DIR:-/tmp/naive-test}/naive.lock"
  NAIVE_CADDY_DIR="${NAIVE_DATA_DIR}/caddy"
  NAIVE_CA_DIR="${NAIVE_DATA_DIR}/ca"
  NAIVE_CA_LIVE="${NAIVE_CA_DIR}/live"
  NAIVE_CERT_FILE="${NAIVE_CA_LIVE}/naive.crt"
  NAIVE_KEY_FILE="${NAIVE_CA_LIVE}/naive.key"
  NAIVE_MASQUERADE="${NAIVE_DATA_DIR}/masquerade"
  NAIVE_CONF="${NAIVE_DATA_DIR}/naive.conf"
  NAIVE_USERS="${NAIVE_DATA_DIR}/users.json"
  NAIVE_STATE="${NAIVE_DATA_DIR}/state.json"
  NAIVE_CADDY_JSON="${NAIVE_CADDY_DIR}/caddy.json"
  NAIVE_CADDY_BAK="${NAIVE_CADDY_DIR}/caddy.json.bak"
fi
