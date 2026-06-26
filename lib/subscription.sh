# lib/subscription.sh — форматы шаринга credentials:
#   1) одиночный URI  https://user:pass@host:443#name
#   2) base64 список URI
#   3) naive-клиент JSON {"listen":"socks://127.0.0.1:1080","proxy":"https://user:pass@host"}
#
# Подменю Users вызывает эти функции через _sub_show_*, которые объявлены
# как no-op в users.sh и перекрываются здесь.

# --- низкоуровневые ---

# URL-encode для URI (RFC 3986, минимальный — alnum + -._~ остаются)
urlencode() {
  jq -rn --arg v "$1" '$v | @uri'
}

# Собрать URI для одного юзера
# sub_uri <name> [<pass>]
# Если пароль не передан — достаётся из users.json
sub_uri() {
  local name="$1" pass="${2-}" host="${NAIVE_DOMAIN}" port="${NAIVE_BIND_PORT:-443}"
  if [[ -z "$pass" ]]; then
    local data; data=$(users_get "$name") || die "user '$name' not found"
    pass=$(printf "%s" "$data" | jq -r .pass)
  fi
  local enc_pass; enc_pass=$(urlencode "$pass")
  printf "https://%s:%s@%s:%s#%s\n" "$name" "$enc_pass" "$host" "$port" "$name"
}

# Получить все credentials разом
sub_all_pairs() {
  [[ -f "$NAIVE_USERS" ]] || return 0
  jq -c '.users[] | {name, pass}' "$NAIVE_USERS"
}

# --- форматы ---

# sub_creds: распечатать user:pass для одного юзера (plain)
sub_creds() {
  local name="$1" data pass
  data=$(users_get "$name") || die "user '$name' not found"
  pass=$(printf "%s" "$data" | jq -r .pass)
  printf "  user: %s\n  pass: %s\n" "$name" "$pass"
}

# sub_loginpass: одна строка "user:pass"
sub_loginpass() {
  local name="$1" data pass
  data=$(users_get "$name") || die "user '$name' not found"
  pass=$(printf "%s" "$data" | jq -r .pass)
  printf "%s:%s\n" "$name" "$pass"
}

# sub_b64: base64 newline-список URI всех юзеров
sub_b64() {
  local uris=""
  while IFS=$'\t' read -r name pass; do
    [[ -z "$name" ]] && continue
    uris+="$(sub_uri "$name" "$pass")"$'\n'
  done < <(sub_all_pairs)
  printf "%s" "$uris" | base64 -w0
  printf "\n"
}

# sub_naive_json_all: массив naive-конфигов (по одному на юзера, порт 1080+idx)
sub_naive_json_all() {
  local arr="[]" idx=0
  while IFS=$'\t' read -r name pass; do
    [[ -z "$name" ]] && continue
    local port=$((1080 + idx))
    local enc_pass; enc_pass=$(urlencode "$pass")
    local host="${NAIVE_DOMAIN}" port443="${NAIVE_BIND_PORT:-443}"
    arr=$(jq -c --argjson a "$arr" --argjson cfg \
      "$(jq -nc --arg l "socks://127.0.0.1:$port" \
                  --arg p "https://$name:$enc_pass@$host:$port443" \
                  '{listen:$l, proxy:$p}')" \
      '$a + [$cfg]')
    idx=$((idx+1))
  done < <(sub_all_pairs)
  printf "%s\n" "$arr"
}

# sub_naive_json_one: один naive-конфиг для одного юзера
sub_naive_json_one() {
  local name="$1" data pass
  data=$(users_get "$name") || die "user '$name' not found"
  pass=$(printf "%s" "$data" | jq -r .pass)
  local enc_pass; enc_pass=$(urlencode "$pass")
  jq -nc --arg l "socks://127.0.0.1:1080" \
           --arg p "https://$name:$enc_pass@${NAIVE_DOMAIN}:${NAIVE_BIND_PORT:-443}" \
           '{listen:$l, proxy:$p}'
}

# --- обёртки для users_menu ---

_sub_show_creds()     { sub_creds    "$1"; }
_sub_show_uri()       { sub_uri      "$1"; }
_sub_show_loginpass() { sub_loginpass "$1"; }
_sub_show_qr()        { qr_uri       "$1"; }
_sub_show_json_single() {
  local name="$1"
  sub_naive_json_one "$name"
  printf "\n  ↑ save with:  naive-client-%s.json > '/path/naive-client-%s.json'\n" "$name" "$name"
  log_warn "JSON содержит пароль в plaintext — не оставляйте файл в /tmp"
}
_sub_show_json_all()  {
  printf "Choose: 1) single user, 2) all users (array)\n"
  prompt_choice 2 || return 0
  case "$CHOICE" in
    1)
      local n; n=$(prompt "Username" "")
      [[ -z "$n" ]] && return
      sub_naive_json_one "$n"
      printf "\n  ↑ save with:  ... > '/path/naive-client-%s.json'\n" "$n"
      log_warn "JSON содержит пароли в plaintext — не оставляйте файл в /tmp"
      ;;
    2) sub_naive_json_all
       printf "\n  ↑ save with:  ... > '/path/naive-clients.json'\n"
       log_warn "JSON содержит пароли в plaintext — не оставляйте файл в /tmp"
       ;;
  esac
}
_sub_show_b64() {
  sub_b64
  printf "\n  ↑ base64 list of all users (paste into subscription URL)\n"
  log_warn "base64 — не шифрование, пароли читаются после декодирования"
}