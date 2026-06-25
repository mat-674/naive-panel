# lib/users.sh — CRUD для /etc/naive/users.json
#
# Формат users.json:
# {
#   "version": 1,
#   "users": [
#     {"name":"alice","pass":"...","created":1750000000,"updated":1750000000}
#   ]
# }
#
# Пароль — plaintext (вынужденно: протокол basicauth не поддерживает хэши).
# Файл chmod 0600.

require_cmd jq "install with: apt install jq"

# --- низкоуровневые операции (с flock) ---

# Прочитать массив users в stdout (JSON-массив)
_users_read() {
  [[ -f "$NAIVE_USERS" ]] || { printf '[]\n'; return 0; }
  jq -c '.users // []' "$NAIVE_USERS"
}

# Записать users (принимает JSON-строку-массив в stdin)
_users_write() {
  local payload
  payload=$(jq -c '{version:1, users: .}')
  printf '%s\n' "$payload" | json_atomic "$NAIVE_USERS" 0600
}

# Захватить flock + выполнить критическую секцию
_users_locked() {
  with_lock "$@"
}

# --- публичный API ---

# users_list: печатает таблицу (id|name|created) в stdout
users_list() {
  _users_read | jq -r '
    .[] | [(.name // ""), (.created // 0 | todate // "unknown")] | @tsv
  ' | awk -F'\t' 'BEGIN{printf "%-4s %-32s %s\n","#","NAME","CREATED"} {printf "%-4d %-32s %s\n", NR, $1, $2}'
}

# users_exists <name>
users_exists() {
  local name="$1"
  _users_read | jq -e --arg n "$name" 'any(.[]; .name == $n)' >/dev/null
}

# users_count
users_count() {
  _users_read | jq 'length'
}

# users_get <name>  — печатает JSON-объект юзера
users_get() {
  local name="$1"
  _users_read | jq -c --arg n "$name" '.[] | select(.name == $n)' | head -1
}

# users_add <name> [<password>]
# Если пароль не передан — генерируется.
users_add() {
  local name="$1" pass="${2:-}"
  [[ -n "$name" ]] || die "username required"

  # Валидация имени: [a-z0-9_-], 1..32 символа, не начинается с '-'
  if ! [[ "$name" =~ ^[a-z0-9_][a-z0-9_-]{0,31}$ ]]; then
    die "invalid username '$name' (allowed: [a-z0-9_-], up to 32 chars, no leading dash)"
  fi

  _users_locked _users_add_impl "$name" "$pass"
}

_users_add_impl() {
  local name="$1" pass="$2"
  if users_exists "$name"; then
    die "user '$name' already exists"
  fi
  [[ -z "$pass" ]] && pass="$(rand_password)"

  local now
  now=$(date +%s)

  _users_read | jq --arg n "$name" --arg p "$pass" --argjson c "$now" --argjson u "$now" \
    '. + [{name:$n, pass:$p, created:$c, updated:$u}]' \
    | _users_write

  log_ok "user '$name' added"
  printf "%s\n" "$pass" > /tmp/naive-last-pass.$$
  log_info "password: $pass"
}

# users_delete <name>
users_delete() {
  local name="$1"
  [[ -n "$name" ]] || die "username required"
  _users_locked _users_delete_impl "$name"
}

_users_delete_impl() {
  local name="$1"
  if ! users_exists "$name"; then
    die "user '$name' not found"
  fi
  _users_read | jq --arg n "$name" 'map(select(.name != $n))' | _users_write
  log_ok "user '$name' deleted"
}

# users_rename <old> <new>
users_rename() {
  local old="$1" new="$2"
  [[ -n "$old" && -n "$new" ]] || die "old and new name required"
  if ! [[ "$new" =~ ^[a-z0-9_][a-z0-9_-]{0,31}$ ]]; then
    die "invalid new username '$new'"
  fi
  _users_locked _users_rename_impl "$old" "$new"
}

_users_rename_impl() {
  local old="$1" new="$2"
  if ! users_exists "$old"; then die "user '$old' not found"; fi
  if users_exists "$new"; then die "user '$new' already exists"; fi
  local now; now=$(date +%s)
  _users_read \
    | jq --arg o "$old" --arg n "$new" --argjson u "$now" \
        'map(if .name == $o then .name = $n | .updated = $u else . end)' \
    | _users_write
  log_ok "renamed '$old' -> '$new'"
}

# users_reset_pass <name> [<new_pass>]
users_reset_pass() {
  local name="$1" pass="${2:-}"
  [[ -n "$name" ]] || die "username required"
  _users_locked _users_reset_pass_impl "$name" "$pass"
}

_users_reset_pass_impl() {
  local name="$1" pass="$2"
  if ! users_exists "$name"; then die "user '$name' not found"; fi
  [[ -z "$pass" ]] && pass="$(rand_password)"
  local now; now=$(date +%s)
  _users_read | jq --arg n "$name" --arg p "$pass" --argjson u "$now" \
    'map(if .name == $n then .pass = $p | .updated = $u else . end)' \
    | _users_write
  log_ok "password for '$name' reset"
  log_info "new password: $pass"
}

# --- users_menu: список юзеров вверху, выбор юзера → его суб-меню ---
#
#   ============================================================
#     Naive-Panel  v0.1.0
#   ------------------------------------------------------------
#     Users
#   ============================================================
#       #   NAME                CREATED
#       1   alice               2026-06-26T...
#       2   bob                 2026-06-26T...
#     + 3. Add user
#     0. Back
#   ------------------------------------------------------------
#   Select [0-3]: 1
#   ── user: alice ──
#     1. Rename
#     2. Reset password
#     3. Show credentials
#     4. Show connection URI
#     5. Show QR code
#     6. Show login:password
#     7. Show naive-client JSON (single)
#     8. Delete
#     0. Back
#
users_menu() {
  while :; do
    banner "Users"

    # Читаем список юзеров в массив имён
    local -a names
    mapfile -t names < <(_users_read | jq -r '.[] | .name')

    printf "  %-4s %-32s %s\n" "#" "NAME" "CREATED"
    if [[ ${#names[@]} -eq 0 ]]; then
      printf "  %s(no users yet)%s\n" "$C_DIM" "$C_RST"
    else
      local i created
      for i in "${!names[@]}"; do
        created=$(users_get "${names[$i]}" | jq -r '.created // 0 | todate // "unknown"')
        printf "  %-4d %-32s %s\n" "$((i+1))" "${names[$i]}" "$created"
      done
    fi
    printf "  %s+ %d. Add user%s\n" "$C_GRN" "$((${#names[@]}+1))" "$C_RST"
    printf "  %s0. Back%s\n" "$C_DIM" "$C_RST"
    printf -- "-------------------------------------------------------------\n"
    prompt_choice "$((${#names[@]}+1))" || return 0

    # 0 — назад
    (( CHOICE == 0 )) && return 0
    # последний пункт — Add
    if (( CHOICE == ${#names[@]}+1 )); then
      _users_ui_add
      printf "\n"
      continue
    fi
    # иначе — выбор существующего юзера
    local selected="${names[$((CHOICE-1))]}"
    _users_user_menu "$selected"
    printf "\n"
  done
}

# _users_user_menu <name> — операции над конкретным юзером
_users_user_menu() {
  local name="$1"
  while :; do
    banner "user: $name"
    # Быстрая сводка
    local data created
    data=$(users_get "$name")
    created=$(printf "%s" "$data" | jq -r '.created // 0 | todate // "?"')
    printf "  created: %s\n\n" "$created"

    cat <<EOF
  1. Rename
  2. Reset password
  3. Show credentials
  4. Show connection URI
  5. Show QR code
  6. Show login:password
  7. Show naive-client JSON (single)
  8. Delete user
  0. Back
EOF
    printf -- "-------------------------------------------------------------\n"
    prompt_choice 8 || return 0
    case "$CHOICE" in
      1) _users_ui_rename_one "$name" ;;
      2) _users_ui_reset_one   "$name" ;;
      3) _sub_show_creds       "$name" ;;
      4) _sub_show_uri         "$name" ;;
      5) _sub_show_qr          "$name" ;;
      6) _sub_show_loginpass   "$name" ;;
      7) _sub_show_json_single "$name" ;;
      8) _users_ui_delete_one  "$name" && return 0 ;;
      0) return 0 ;;
    esac
    printf "\n"
  done
}

# --- операции для одного юзера (без запроса имени — оно известно) ---

_users_ui_rename_one() {
  local old="$1" new
  new=$(prompt "New username" "$old")
  [[ -z "$new" || "$new" == "$old" ]] && { log_warn "aborted"; return; }
  users_rename "$old" "$new" || return 1
  caddy_reload_safe || log_warn "config reload failed"
}

_users_ui_reset_one() {
  local name="$1" pass
  if prompt_confirm "Generate random password? [Y/n]" Y; then
    pass=""
  else
    pass=$(prompt_secret "New password (min 8 chars)")
    [[ "${#pass}" -lt 8 ]] && { log_err "password too short"; return 1; }
  fi
  users_reset_pass "$name" "$pass" || return 1
  caddy_reload_safe || log_warn "config reload failed"
}

_users_ui_delete_one() {
  local name="$1"
  prompt_confirm "Really delete '$name'? [y/N]" N || return 1
  users_delete "$name" || return 1
  caddy_reload_safe || log_warn "config reload failed"
  log_ok "user '$name' deleted"
}

# --- оставлены для обратной совместимости со старыми _users_ui_* вызовами ---
# (раньше users_menu вызывал _users_ui_creds и т.п. напрямую — теперь эти
# функции вызываются из _users_user_menu с уже известным именем.)

_users_ui_creds()      { local n; n=$(prompt "Username" ""); [[ -n "$n" ]] && _sub_show_creds "$n"; }
_users_ui_uri()        { local n; n=$(prompt "Username" ""); [[ -n "$n" ]] && _sub_show_uri   "$n"; }
_users_ui_qr()         { local n; n=$(prompt "Username" ""); [[ -n "$n" ]] && _sub_show_qr    "$n"; }
_users_ui_loginpass()  { local n; n=$(prompt "Username" ""); [[ -n "$n" ]] && _sub_show_loginpass "$n"; }
_users_ui_json()       { _sub_show_json_all; }
_users_ui_b64()        { _sub_show_b64; }

# _sub_show_json_single: per-user JSON-конфиг (для пункта 7 в user-меню)
# Объявлен как no-op здесь, перекрывается в lib/subscription.sh если есть.
if ! declare -F _sub_show_json_single >/dev/null; then
  _sub_show_json_single() { log_warn "_sub_show_json_single not implemented"; }
fi

# --- UI-обработчики (вызывают lib/subscription.sh, lib/qr.sh) ---
# Каждый — обёртка над интерактивным вводом + соответствующей функцией.

_users_ui_add() {
  local name pass
  name=$(prompt "Username" "")
  [[ -z "$name" ]] && { log_warn "aborted"; return; }
  if prompt_confirm "Generate random password? [Y/n]" Y; then
    pass=""
  else
    pass=$(prompt_secret "Password (min 8 chars)")
    [[ "${#pass}" -lt 8 ]] && { log_err "password too short"; return 1; }
  fi
  users_add "$name" "$pass" || return 1
  caddy_reload_safe || log_warn "config reload failed — fix manually"
}

_users_ui_delete() {
  local name
  name=$(prompt "Username to delete" "")
  [[ -z "$name" ]] && return
  if ! users_exists "$name"; then log_err "user '$name' not found"; return 1; fi
  prompt_confirm "Really delete '$name'? [y/N]" N || return
  users_delete "$name" || return 1
  caddy_reload_safe || log_warn "config reload failed"
}

_users_ui_rename() {
  local old new
  old=$(prompt "Old username" "")
  new=$(prompt "New username" "")
  [[ -z "$old" || -z "$new" ]] && return
  users_rename "$old" "$new" || return 1
  caddy_reload_safe || log_warn "config reload failed"
}

_users_ui_reset() {
  local name pass
  name=$(prompt "Username" "")
  [[ -z "$name" ]] && return
  if prompt_confirm "Generate random password? [Y/n]" Y; then
    pass=""
  else
    pass=$(prompt_secret "New password (min 8 chars)")
    [[ "${#pass}" -lt 8 ]] && { log_err "password too short"; return 1; }
  fi
  users_reset_pass "$name" "$pass" || return 1
  caddy_reload_safe || log_warn "config reload failed"
}

_users_ui_creds()   { _users_ui_pick_user _sub_show_creds; }
_users_ui_uri()     { _users_ui_pick_user _sub_show_uri; }
_users_ui_qr()      { _users_ui_pick_user _sub_show_qr; }
_users_ui_loginpass(){ _users_ui_pick_user _sub_show_loginpass; }
_users_ui_json()    { _sub_show_json_all; }
_users_ui_b64()     { _sub_show_b64; }

# _users_ui_pick_user: общий ввод имени (для одиночных подменю)
_users_ui_pick_user() {
  local fn="$1" name
  name=$(prompt "Username" "")
  [[ -z "$name" ]] && return
  if ! users_exists "$name"; then log_err "user '$name' not found"; return 1; fi
  "$fn" "$name"
}

# --- info_summary: для cmd_info (пункт 9 главного меню) ---
info_summary() {
  banner "$(status_summary)"
  printf "  Users: %s\n" "$(users_count)"
  users_list
  printf "\n  For per-user share URI/QR, see Users menu.\n"
}
