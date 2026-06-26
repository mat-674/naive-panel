# lib/caddy_config.sh — рендер /etc/naive/caddy/caddy.json из users.json + naive.conf
#
# Алгоритм:
#   1) сгенерировать auth_credentials (массив {username,password}) через jq
#   2) выбрать MASQUERADE_HANDLER: file_server или reverse_proxy
#   3) подставить все маркеры __X__ в templates/caddy.json.tpl → caddy.json
#   4) валидировать через `caddy validate --config ...` (если caddy в PATH)

require_cmd jq "install with: apt install jq"

# Путь к шаблону (ищется и в $NAIVE_PANEL_DIR/templates, и в lib/.. для dev)
_caddy_template() {
  local candidates=(
    "$NAIVE_PANEL_DIR/templates/caddy.json.tpl"
    "${BASH_SOURCE[0]%/*}/../templates/caddy.json.tpl"
  )
  for p in "${candidates[@]}"; do
    [[ -f "$p" ]] && { printf "%s" "$p"; return 0; }
  done
  die "caddy.json.tpl not found"
}

# Сгенерировать JSON-фрагмент auth_credentials из users.json
# Печатает в stdout JSON-массив: [{"username":"alice","password":"..."},...]
_user_creds_json() {
  if [[ ! -f "$NAIVE_USERS" ]]; then
    printf '[]\n'
    return 0
  fi
  jq -c '[.users[] | {username: .name, password: .pass}]' "$NAIVE_USERS" 2>/dev/null \
    || printf '[]\n'
}

# Выбрать MASQUERADE_HANDLER — JSON-фрагмент, вставляемый в routes[0].handle.
# Всегда возвращает ОДНУ СТРОКУ (jq -c), чтобы sed-подстановка не ломалась.
# Возможные kind: default|minimal|blog|docs|custom-dir|custom-url
_masquerade_handler() {
  local kind="$1" dir="$2" url="$3"
  case "$kind" in
    custom-url)
      [[ -z "$url" ]] && die "custom-url masquerade requires MASQUERADE_URL"
      jq -nc --arg u "$url" '{handler:"reverse_proxy", upstreams:[{dial:$u}]}'
      ;;
    custom-dir|''|default|minimal|blog|docs)
      [[ -z "$dir" ]] && dir="/var/www/html"
      jq -nc --arg r "$dir" '{handler:"file_server", root:$r}'
      ;;
    *)
      die "unknown masquerade kind: $kind"
      ;;
  esac
}

# caddy_render: перегенерировать caddy.json из текущего состояния
# Возвращает 0 при успехе, 1 при ошибке. НЕ делает reload — это caddy_admin.
caddy_render() {
  [[ -n "$NAIVE_DOMAIN" ]] || { log_warn "NAIVE_DOMAIN is empty — caddy.json may be invalid"; }
  [[ -n "$NAIVE_EMAIL" ]]  || { log_warn "NAIVE_EMAIL is empty — ACME registration may fail"; }

  local tmpl creds handler rendered
  tmpl=$(_caddy_template)
  creds=$(_user_creds_json)
  handler=$(_masquerade_handler "$NAIVE_MASQUERADE_KIND" "$NAIVE_MASQUERADE" "$NAIVE_MASQUERADE_URL")

  # Используем редкий разделитель (\x1F, ASCII Unit Separator) вместо '|',
  # чтобы пароли с вертикальной чертой или JSON-пайплайны не ломали sed.
  # $'...' нужно чтобы bash раскрыл \x1F (внутри "..." он литерален).
  rendered=$(sed \
    -e $'s\x1f__USER_CREDS__\x1f'"$creds"$'\x1fg' \
    -e $'s\x1f__MASQUERADE_HANDLER__\x1f'"$handler"$'\x1fg' \
    -e $'s\x1f__DOMAIN__\x1f'"$NAIVE_DOMAIN"$'\x1fg' \
    -e $'s\x1f__EMAIL__\x1f'"$NAIVE_EMAIL"$'\x1fg' \
    -e $'s\x1f__LOG_DIR__\x1f'"$NAIVE_LOG_DIR"$'\x1fg' \
    -e $'s\x1f__BIND_PORT__\x1f'"${NAIVE_BIND_PORT:-443}"$'\x1fg' \
    "$tmpl")

  # Валидация синтаксиса JSON (без caddy — на CI, где caddy не установлен)
  if ! printf "%s" "$rendered" | jq . >/dev/null 2>&1; then
    log_err "rendered caddy.json is not valid JSON"
    return 1
  fi

  # Бэкап текущего валидного (если есть)
  [[ -f "$NAIVE_CADDY_JSON" ]] && cp -f "$NAIVE_CADDY_JSON" "$NAIVE_CADDY_BAK"

  # Запись
  printf "%s" "$rendered" | json_atomic "$NAIVE_CADDY_JSON" 0644
  log_ok "caddy.json rendered"
  return 0
}

# caddy_validate: запустить `caddy validate --config ...` если caddy в PATH
# Возвращает 0 если caddy отсутствует (тогда пропускаем — поведение для CI)
caddy_validate() {
  if ! command -v caddy >/dev/null 2>&1; then
    log_info "caddy not installed, skipping validation"
    return 0
  fi
  if caddy validate --config "$NAIVE_CADDY_JSON" 2>&1 | tee /tmp/caddy-validate.$$.log; then
    log_ok "caddy.json is valid"
    rm -f /tmp/caddy-validate.$$.log
    return 0
  else
    log_err "caddy.json is invalid — see /tmp/caddy-validate.$$.log"
    return 1
  fi
}