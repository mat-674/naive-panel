#!/usr/bin/env bash
# tests/test_render_caddy_json.sh — golden-тесты рендера caddy.json.
# Не требует установленного caddy. Проверяет:
#   - caddy.json валиден как JSON
#   - содержит правильные auth_credentials для users.json
#   - MASQUERADE_HANDLER соответствует kind
#   - домен/email/log_dir подставлены

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TESTDIR="/tmp/naive-cfg-test-$$"
export NAIVE_TEST_MODE=1
export NAIVE_TEST_DIR="$TESTDIR"

source "$ROOT/lib/common.sh"
source "$ROOT/lib/config.sh"
source "$ROOT/lib/users.sh"
source "$ROOT/lib/caddy_config.sh"

PASS=0; FAIL=0
pass() { printf "  %sPASS%s %s\n" "$C_GRN" "$C_RST" "$*"; PASS=$((PASS+1)); }
fail() { printf "  %sFAIL%s %s\n" "$C_RED" "$C_RST" "$*"; FAIL=$((FAIL+1)); }
assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [[ "$got" == "$want" ]]; then pass "$msg (= $got)"; else fail "$msg: got '$got' want '$want'"; fi
}

mkdir -p "$TESTDIR"
ensure_dirs

# --- сценарий 1: domain + default masquerade + 0 users ---
NAIVE_MODE="domain"
NAIVE_DOMAIN="example.com"
NAIVE_EMAIL="admin@example.com"
NAIVE_MASQUERADE_KIND="default"
NAIVE_MASQUERADE="/etc/naive/masquerade"
NAIVE_MASQUERADE_URL=""
caddy_render || { fail "render failed"; exit 1; }

# Проверка JSON
if jq -e . "$NAIVE_CADDY_JSON" >/dev/null 2>&1; then pass "valid JSON"; else fail "invalid JSON"; fi

# Проверка auth_credentials пуст
creds=$(jq -c '.apps.http.servers.proxy.routes[1].handle[0].auth_credentials' "$NAIVE_CADDY_JSON")
assert_eq "$creds" "[]" "auth_credentials empty when no users"

# Проверка MASQUERADE_HANDLER = file_server
handler_type=$(jq -r '.apps.http.servers.proxy.routes[0].handle[0].handler' "$NAIVE_CADDY_JSON")
assert_eq "$handler_type" "file_server" "default masquerade uses file_server"

# Проверка подстановки domain (теперь через match SNI, см. tls_connection_policies)
domain=$(jq -r '.apps.http.servers.proxy.tls_connection_policies[0].match.sni[0]' "$NAIVE_CADDY_JSON")
assert_eq "$domain" "example.com" "domain substituted in SNI match"

# Проверка log path
logpath=$(jq -r '.logging.logs.access.output' "$NAIVE_CADDY_JSON")
assert_eq "$logpath" "file://$NAIVE_LOG_DIR/access.log" "log path substituted"

# Проверка путей к сертификату (теперь Caddy подхватывает cert через load_files)
certfile=$(jq -r '.apps.tls.certificates.load_files[0].certificate' "$NAIVE_CADDY_JSON")
keyfile=$(jq -r '.apps.tls.certificates.load_files[0].key' "$NAIVE_CADDY_JSON")
assert_eq "$certfile" "$NAIVE_CERT_FILE" "cert file path substituted"
assert_eq "$keyfile"  "$NAIVE_KEY_FILE"  "key file path substituted"

# Проверка что встроенный ACME удалён (ранее был тут .apps.tls.automation)
if jq -e '.apps.tls.automation' "$NAIVE_CADDY_JSON" >/dev/null 2>&1; then
  fail "inbuilt ACME automation should be removed"
else
  pass "no inbuilt ACME automation (single source: acme.sh)"
fi

# --- сценарий 2: тот же domain + 2 users ---
users_add alice "Pa55!"
users_add bob "Hunter2!"
caddy_render
creds=$(jq -c '.apps.http.servers.proxy.routes[1].handle[0].auth_credentials' "$NAIVE_CADDY_JSON")
expected='[{"username":"alice","password":"Pa55!"},{"username":"bob","password":"Hunter2!"}]'
assert_eq "$creds" "$expected" "auth_credentials has 2 users"

# --- сценарий 3: custom-url masquerade ---
NAIVE_MASQUERADE_KIND="custom-url"
NAIVE_MASQUERADE_URL="https://example.org"
caddy_render
handler_type=$(jq -r '.apps.http.servers.proxy.routes[0].handle[0].handler' "$NAIVE_CADDY_JSON")
assert_eq "$handler_type" "reverse_proxy" "custom-url uses reverse_proxy"
dial=$(jq -r '.apps.http.servers.proxy.routes[0].handle[0].upstreams[0].dial' "$NAIVE_CADDY_JSON")
assert_eq "$dial" "https://example.org" "upstream dial set"

# --- сценарий 4: caddy_config не падает на пустых users ---
# (уже проверено в сценарии 1, но добавим отдельный свежий TESTDIR)
TESTDIR2="/tmp/naive-cfg-test2-$$"
NAIVE_TEST_DIR="$TESTDIR2"
mkdir -p "$TESTDIR2/etc/caddy" "$TESTDIR2/log"
NAIVE_CADDY_JSON="$NAIVE_TEST_DIR/etc/caddy/caddy.json"
NAIVE_USERS="$NAIVE_TEST_DIR/etc/users.json"
NAIVE_LOG_DIR="$NAIVE_TEST_DIR/log"
caddy_render
if [[ -f "$NAIVE_CADDY_JSON" ]]; then pass "render works in fresh dir"; else fail "no caddy.json"; fi

# --- итог ---
printf "\n--- caddy render tests: %d passed, %d failed\n" "$PASS" "$FAIL"
rm -rf "$TESTDIR" "$TESTDIR2"
exit $((FAIL > 0 ? 1 : 0))