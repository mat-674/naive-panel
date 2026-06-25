# lib/common.sh — общие хелперы: логгер, цвета, prompt, flock, atomic-write.
# Подгружается остальными lib/*.sh. Не рассчитан на прямой запуск.

# --- цвета (если tty) ---
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_BLU=$'\033[34m'; C_DIM=$'\033[2m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_DIM=""; C_BLD=""; C_RST=""
fi

log_info()  { printf "%s[i]%s %s\n" "$C_BLU"  "$C_RST" "$*"; }
log_ok()    { printf "%s[+]%s %s\n" "$C_GRN"  "$C_RST" "$*"; }
log_warn()  { printf "%s[!]%s %s\n" "$C_YEL"  "$C_RST" "$*" >&2; }
log_err()   { printf "%s[x]%s %s\n" "$C_RED"  "$C_RST" "$*" >&2; }
log_step()  { printf "\n%s==>%s %s\n" "$C_BLD$C_BLU" "$C_RST" "$*"; }

die() { log_err "$*"; exit 1; }

# --- prompt: запрашивает строку, не пустую, с дефолтом $2 ---
prompt() {
  local label="$1" default="${2:-}" answer
  if [[ -n "$default" ]]; then
    printf "%s [%s]: " "$label" "$default"
  else
    printf "%s: " "$label"
  fi
  if ! read -r answer; then
    # EOF: применяем дефолт если есть, иначе проваливаемся
    [[ -n "$default" ]] && printf "%s" "$default" && return 0
    return 1
  fi
  [[ -z "$answer" && -n "$default" ]] && answer="$default"
  printf "%s" "$answer"
}

# --- prompt_secret: скрытый ввод (для паролей) ---
prompt_secret() {
  local label="$1" answer
  printf "%s: " "$label"
  if ! read -rs answer; then
    printf "\n"
    return 1
  fi
  printf "\n"
  printf "%s" "$answer"
}

# --- prompt_confirm: y/N ---
prompt_confirm() {
  local label="$1" default="${2:-N}" answer
  printf "%s [y/N]: " "$label"
  if ! read -r answer; then return 1; fi
  [[ -z "$answer" ]] && answer="$default"
  [[ "$answer" =~ ^[Yy]$ ]]
}

# --- prompt_choice: цифровой выбор в диапазоне 0..N ---
# Результат — в $CHOICE (глобальная переменная). Возвращает 0 при успехе,
# 1 при EOF на stdin (с $CHOICE=0, чтобы вызывающий код не крутился вечно).
prompt_choice() {
  local max="$1" answer
  CHOICE=0
  while :; do
    printf "Select [0-%d]: " "$max"
    if ! read -r answer; then
      log_warn "stdin closed, exiting."
      return 1
    fi
    if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 0 && answer <= max )); then
      CHOICE=$answer
      return 0
    fi
    log_warn "Invalid choice, try again."
  done
}

# --- require_root: проверяет EUID 0 ---
require_root() {
  (( EUID == 0 )) || die "must be run as root (use sudo)"
}

# --- require_cmd: проверяет наличие команды ---
require_cmd() {
  local cmd="$1" hint="${2:-}"
  command -v "$cmd" >/dev/null 2>&1 || die "missing command: $cmd${hint:+ — $hint}"
}

# --- atomic_write: tmp + mv (POSIX-атомарно в пределах одного ФС) ---
atomic_write() {
  local path="$1" content="$2" mode="${3:-0644}"
  local dir tmp
  dir="$(dirname "$path")"
  [[ -d "$dir" ]] || mkdir -p "$dir"
  tmp="$(mktemp "${dir}/.${RANDOM}.XXXXXX")"
  printf "%s" "$content" > "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$path"
}

# --- json_atomic: то же, но для данных, требующих валидного JSON на выходе ---
# Использование: echo "$json" | json_atomic FILE 0600
json_atomic() {
  local path="$1" mode="${2:-0600}"
  local dir tmp
  dir="$(dirname "$path")"
  [[ -d "$dir" ]] || mkdir -p "$dir"
  tmp="$(mktemp "${dir}/.${RANDOM}.XXXXXX")"
  cat > "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$path"
  # mv на некоторых FS (особенно Windows/Git Bash) не сохраняет mode — выставим явно
  chmod "$mode" "$path" 2>/dev/null || true
}

# --- with_lock: выполняет функцию под flock /var/lock/naive.lock ---
# Приоритеты:
#   1) flock(1) — нативно на Linux
#   2) mkdir-as-lock — переносимо везде (атомарно на POSIX; на Windows mkdir
#      тоже атомарен в рамках одной ФС — этого достаточно для single-user CLI).
with_lock() {
  local lockfile="${NAIVE_LOCK:-/var/lock/naive.lock}"
  [[ -d "$(dirname "$lockfile")" ]] || mkdir -p "$(dirname "$lockfile")"

  if command -v flock >/dev/null 2>&1; then
    exec 9>"$lockfile"
    flock -n 9 || die "another naive instance is running"
    "$@"
    return $?
  fi

  # mkdir-fallback
  if mkdir "$lockfile.lock" 2>/dev/null; then
    # trap на EXIT снимет lock при выходе (включая crash через die→exit)
    trap 'rmdir "${NAIVE_LOCK:-/var/lock/naive.lock}.lock" 2>/dev/null || true' EXIT
    "$@"
    local rc=$?
    rmdir "${NAIVE_LOCK:-/var/lock/naive.lock}.lock" 2>/dev/null || true
    trap - EXIT
    return $rc
  else
    die "another naive instance is running (lock: $lockfile.lock)"
  fi
}

# --- rand_password: 18 байт base64 (~144 бит энтропии), trim padding ---
rand_password() {
  openssl rand -base64 18 | tr -d '=/+\n' | cut -c1-20
}

# --- banner: ASCII-шапка в каждом подменю ---
banner() {
  local title="$1"
  printf "%s\n" "============================================================="
  printf "  %s  v%s\n" "$NAIVE_TITLE" "$NAIVE_VERSION"
  printf "%s\n" "-------------------------------------------------------------"
  printf "  %s\n" "$title"
  printf "%s\n" "============================================================="
}
