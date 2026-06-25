#!/usr/bin/env bash
# tests/test_users.sh — герметичные тесты CRUD для lib/users.sh.
# Не требует bats. Запускается так:
#   bash tests/test_users.sh
#
# Использует NAIVE_TEST_MODE=1, чтобы все пути ушли в /tmp/naive-test.

set -uo pipefail  # намеренно без -e: некоторые тесты ожидают fail от users_add

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TESTDIR="/tmp/naive-test-$$"
export NAIVE_TEST_MODE=1
export NAIVE_TEST_DIR="$TESTDIR"

# Подгружаем модули напрямую (не через dispatcher)
source "$ROOT/lib/common.sh"
source "$ROOT/lib/config.sh"
source "$ROOT/lib/users.sh"

# Счётчики
PASS=0; FAIL=0
fail() { printf "  %sFAIL%s  %s\n" "$C_RED" "$C_RST" "$*"; FAIL=$((FAIL+1)); }
pass() { printf "  %sPASS%s  %s\n" "$C_GRN" "$C_RST" "$*"; PASS=$((PASS+1)); }
assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [[ "$got" == "$want" ]]; then pass "$msg (=$got)"; else fail "$msg: got '$got' want '$want'"; fi
}
assert_match() {
  local got="$1" pat="$2" msg="$3"
  if [[ "$got" =~ $pat ]]; then pass "$msg"; else fail "$msg: '$got' doesn't match /$pat/"; fi
}

# --- инициализация ---
mkdir -p "$TESTDIR"
ensure_dirs

# --- кейсы ---

# t1: пустой users.json отсутствует; users_count -> 0
assert_eq "$(users_count)" "0" "users_count starts at 0"

# t2: добавление валидного юзера
users_add alice "Pa55w0rd!"
assert_eq "$(users_count)" "1" "after add alice, count=1"
assert_eq "$(users_exists alice && echo y || echo n)" "y" "alice exists"

# t3: повторное добавление должно падать
# Оборачиваем в subshell, иначе die→exit 1 убивает весь тестовый скрипт
if (users_add alice "x") 2>/dev/null; then
  fail "duplicate add should fail"
else
  pass "duplicate add fails"
fi

# t4: невалидное имя отклоняется (subshell — иначе die→exit 1)
for bad in "" "-leading" "UPPER" "with space" "toolongnamewithtoomanychars_xxxxxxxx"; do
  if (users_add "$bad" "p") 2>/dev/null; then
    fail "invalid name '$bad' should be rejected"
  else
    pass "invalid name '$bad' rejected"
  fi
done

# t5: добавление второго юзера
users_add bob "Hunter2!"
assert_eq "$(users_count)" "2" "after add bob, count=2"

# t6: rename
users_rename alice "alice2"
assert_eq "$(users_exists alice2 && echo y || echo n)" "y" "alice renamed to alice2"
assert_eq "$(users_exists alice && echo y || echo n)" "n" "old alice name gone"

# t7: reset password
oldpass=$(users_get alice2 | jq -r .pass)
users_reset_pass alice2 "NewPass99"
newpass=$(users_get alice2 | jq -r .pass)
assert_eq "$oldpass" "Pa55w0rd!" "old pass from file is Pa55w0rd!"
assert_eq "$newpass" "NewPass99" "new pass from file is NewPass99"

# t8: users_get
got=$(users_get bob | jq -r .name)
assert_eq "$got" "bob" "users_get bob returns name"

# t9: delete
users_delete bob
assert_eq "$(users_count)" "1" "after delete bob, count=1"
assert_eq "$(users_exists bob && echo y || echo n)" "n" "bob gone"

# t10: delete несуществующего (subshell)
if (users_delete nobody) 2>/dev/null; then
  fail "delete non-existent should fail"
else
  pass "delete non-existent fails"
fi

# t11: json формат валидный
if jq -e . "$NAIVE_USERS" >/dev/null; then
  pass "users.json is valid JSON"
else
  fail "users.json is not valid JSON"
fi

# t12: структура: version + users[]
ver=$(jq -r .version "$NAIVE_USERS")
type=$(jq -r '.users | type' "$NAIVE_USERS")
assert_eq "$ver" "1" "version=1"
assert_eq "$type" "array" "users is array"

# t13: chmod 0600
# Под Linux — строгая проверка. Под Windows NTFS (msys) mode-биты
# не различаются для group/other, поэтому пропускаем с предупреждением.
if [[ "$(uname -s)" == "Linux" ]]; then
  mode=$(stat -c %a "$NAIVE_USERS" 2>/dev/null)
  assert_eq "$mode" "600" "users.json is chmod 600"
else
  log_warn "skipping chmod 0600 strict check on $(uname -s)"
fi

# --- итог ---
printf "\n"
printf "%s---%s users tests: %d passed, %d failed\n" "$C_BLD" "$C_RST" "$PASS" "$FAIL"
rm -rf "$TESTDIR"
exit $((FAIL > 0 ? 1 : 0))