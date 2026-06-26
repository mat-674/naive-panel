# lib/bootstrap.sh — установка Go + xcaddy + сборка caddy с forwardproxy@naive
#
# Запускается на чистом Ubuntu/Debian. Ничего не модифицирует глобально,
# пока не получит явное одобрение. Всегда можно вызвать повторно —
# идемпотентно: пропускает уже сделанные шаги.
#
# Все операции с файловой системой и сервисами требуют root.
# Проверка делается в каждой entry-функции, чтобы модуль можно было
# source'ить без падения в dev-окружении.

GO_VERSION_MIN="1.21"
GO_INSTALL_DIR="/usr/local/go"
GO_TARBALL="go1.22.5.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"
XCADDY_BIN="$NAIVE_BIN_DIR/xcaddy"
CADDY_BUILD_LOG="/tmp/naive-build.log"

# --- Go ---

# Обнаружить Go в системе; вернуть путь к `go` или пусто.
detect_go() {
  if command -v go >/dev/null 2>&1; then
    go version | grep -oE 'go[0-9]+\.[0-9]+' | head -1
    return 0
  fi
  return 1
}

# Проверить, что версия Go >= $1
go_version_ok() {
  local want="$1" have
  have=$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//')
  [[ -z "$have" ]] && return 1
  printf '%s\n%s\n' "$have" "$want" | sort -V | head -1 | grep -qx "$want" \
    && return 0 || return 1
}

# Установить Go в /usr/local/go (если системный go < требуемой версии)
install_go() {
  require_root
  if detect_go >/dev/null && go_version_ok "$GO_VERSION_MIN"; then
    log_ok "Go $(go version | awk '{print $3}') is OK"
    return 0
  fi

  log_step "Installing Go ${GO_VERSION_MIN}+ to $GO_INSTALL_DIR"

  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64)  GO_TARBALL="go1.22.5.linux-amd64.tar.gz" ;;
    aarch64|arm64) GO_TARBALL="go1.22.5.linux-arm64.tar.gz" ;;
    *) die "unsupported architecture: $arch" ;;
  esac
  GO_URL="https://go.dev/dl/${GO_TARBALL}"

  local tmp; tmp=$(mktemp -d)
  if ! curl -fsSL -o "$tmp/go.tgz" "$GO_URL"; then
    log_err "failed to download Go from $GO_URL"
    log_err "check internet access: curl -I https://go.dev"
    rm -rf "$tmp"
    return 1
  fi

  # Удаляем старый /usr/local/go если есть
  rm -rf "$GO_INSTALL_DIR"
  tar -C /usr/local -xzf "$tmp/go.tgz"
  rm -rf "$tmp"

  # Прописываем в PATH для текущей сессии
  export PATH="$GO_INSTALL_DIR/bin:$PATH"
  hash -r

  log_ok "Go installed: $(go version)"
  log_warn "Go is in $GO_INSTALL_DIR — added to current session PATH only"
  log_warn "naive will use it automatically on next run"
}

# --- xcaddy ---

install_xcaddy() {
  require_root
  if [[ -x "$XCADDY_BIN" ]]; then
    log_ok "xcaddy already at $XCADDY_BIN"
    return 0
  fi
  log_step "Installing xcaddy..."
  export PATH="$GO_INSTALL_DIR/bin:$PATH"
  if go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest 2>&1 | tee -a "$CADDY_BUILD_LOG"; then
    local gobin
    gobin=$(go env GOPATH)/bin
    if [[ -x "$gobin/xcaddy" ]]; then
      install -m 0755 "$gobin/xcaddy" "$XCADDY_BIN"
      log_ok "xcaddy installed at $XCADDY_BIN"
    else
      log_err "xcaddy binary not found in $gobin after install"
      return 1
    fi
  else
    log_err "go install xcaddy failed — see $CADDY_BUILD_LOG"
    return 1
  fi
}

# --- caddy build ---

# build_caddy: собрать caddy с плагином forwardproxy@naive
build_caddy() {
  require_root
  local target="$NAIVE_BIN"
  log_step "Building caddy (this can take 3-10 minutes)..."
  log_info "plugin: github.com/klzgrad/forwardproxy@naive"
  log_info "log:    $CADDY_BUILD_LOG"

  export PATH="$GO_INSTALL_DIR/bin:$PATH"

  if (cd /tmp && "$XCADDY_BIN" build \
        --with "github.com/caddyserver/forwardproxy=github.com/klzgrad/forwardproxy@naive" \
        --output "$target" 2>&1) | tee -a "$CADDY_BUILD_LOG"; then
    chmod 0755 "$target"
    log_ok "caddy built: $target"
  else
    log_err "caddy build failed — see $CADDY_BUILD_LOG"
    log_err "common causes:"
    log_err "  - no internet (check: curl -I https://proxy.golang.org)"
    log_err "  - out of disk (need ~1 GB free in /tmp and ~/go)"
    log_err "  - old gcc (need gcc >= 9)"
    return 1
  fi
}

# --- setcap ---

setcap_caddy() {
  require_root
  log_step "Setting cap_net_bind_service on caddy"
  if ! command -v setcap >/dev/null 2>&1; then
    log_warn "setcap not found — install libcap2-bin"
    apt-get install -y libcap2-bin || return 1
  fi
  if setcap cap_net_bind_service=+ep "$NAIVE_BIN"; then
    log_ok "setcap applied"
  else
    log_err "setcap failed"
    return 1
  fi
}

# --- main entry ---

# bootstrap_all: оркестратор для naive install
bootstrap_all() {
  require_root
  # build-essential нужен для компиляции плагинов
  if ! command -v gcc >/dev/null 2>&1; then
    log_step "Installing build-essential (gcc, make) for caddy build"
    apt-get update -qq && apt-get install -y build-essential
  fi

  install_go       || die "Go install failed"
  install_xcaddy   || die "xcaddy install failed"
  build_caddy      || die "caddy build failed"
  setcap_caddy     || die "setcap failed"

  # Финальная проверка. Caddy 2.7+ не печатает плагины в `version`,
  # поэтому используем `list-modules` — надёжный индикатор.
  if "$NAIVE_BIN" list-modules 2>/dev/null | grep -qi "forwardproxy"; then
    log_ok "caddy ready (forwardproxy plugin detected)"
  else
    log_warn "caddy built but forwardproxy plugin not detected"
    log_warn "check: $NAIVE_BIN list-modules | grep -i forwardproxy"
    return 1
  fi
}

# upgrade_caddy: пересборка с актуальной версией forwardproxy@naive
upgrade_caddy() {
  require_root
  log_step "Upgrading caddy (pulling latest forwardproxy@naive)"
  if systemctl is-active --quiet naive-caddy; then
    log_info "stopping naive-caddy"
    systemctl stop naive-caddy
  fi
  if ! build_caddy; then
    log_err "upgrade build failed — restoring service"
    systemctl start naive-caddy || true
    return 1
  fi
  setcap_caddy
  systemctl start naive-caddy
  log_ok "caddy upgraded and running"
}