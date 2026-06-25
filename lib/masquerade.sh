# lib/masquerade.sh — управление маскирующим сайтом (file_server / reverse_proxy).
#
# Поддерживаемые kind:
#   default|minimal|blog|docs   — копируем встроенный шаблон в $NAIVE_MASQUERADE
#   custom-dir                   — пользователь указывает путь (NAIVE_MASQUERADE)
#   custom-url                   — reverse_proxy на NAIVE_MASQUERADE_URL

# Путь к шаблонам
_masq_template_dir() {
  local candidates=(
    "$NAIVE_PANEL_DIR/templates/masquerade"
    "${BASH_SOURCE[0]%/*}/../templates/masquerade"
  )
  for p in "${candidates[@]}"; do
    [[ -d "$p" ]] && { printf "%s" "$p"; return 0; }
  done
  die "masquerade templates not found"
}

# Копировать шаблон в /etc/naive/masquerade (только для kind из встроенных)
masq_install_template() {
  local kind="$1" src_dir dest_dir
  src_dir=$(_masq_template_dir)
  dest_dir="${NAIVE_MASQUERADE}"

  if [[ ! -d "$src_dir/$kind" ]]; then
    die "unknown masquerade template: $kind"
  fi

  rm -rf "$dest_dir"
  mkdir -p "$dest_dir"
  cp -r "$src_dir/$kind/." "$dest_dir/"
  log_ok "template '$kind' installed to $dest_dir"
}

# Применить настройку (template/custom-dir/custom-url) + перерендерить caddy.json
masq_apply() {
  local kind="$1" dir="$2" url="$3"
  case "$kind" in
    default|minimal|blog|docs)
      NAIVE_MASQUERADE_KIND="$kind"
      masq_install_template "$kind"
      NAIVE_MASQUERADE="/etc/naive/masquerade"
      NAIVE_MASQUERADE_URL=""
      ;;
    custom-dir)
      [[ -z "$dir" ]] && die "custom-dir requires directory path"
      [[ -d "$dir" ]] || die "directory not found: $dir"
      NAIVE_MASQUERADE_KIND="custom-dir"
      NAIVE_MASQUERADE="$dir"
      NAIVE_MASQUERADE_URL=""
      ;;
    custom-url)
      [[ -z "$url" ]] && die "custom-url requires URL"
      NAIVE_MASQUERADE_KIND="custom-url"
      NAIVE_MASQUERADE_URL="$url"
      NAIVE_MASQUERADE=""
      ;;
    *)
      die "unknown kind: $kind"
      ;;
  esac
  write_conf
  caddy_reload_safe
  log_ok "masquerade applied"
}

# masq_preview: показать что увидит посетитель, зашедший на https://DOMAIN/
masq_preview() {
  local url="https://${NAIVE_DOMAIN}/"
  log_info "masquerade is served at: $url"
  printf "\n  curl command:\n"
  printf "    curl -k %s\n" "$url"
  printf "\n  Browser:\n"
  printf "    %s\n" "$url"
}

# masquerade_menu: подменю
masquerade_menu() {
  while :; do
    banner "Masquerade site"
    cat <<EOF
  Current: $NAIVE_MASQUERADE_KIND
  Dir:     $NAIVE_MASQUERADE
  URL:     $NAIVE_MASQUERADE_URL
EOF
    printf "\n"
    cat <<EOF
  1. Use built-in: default
  2. Use built-in: minimal
  3. Use built-in: blog
  4. Use built-in: docs
  5. Custom local directory
  6. Custom remote URL (reverse-proxy pass-through)
  7. Preview
  0. Back
EOF
    printf -- "-------------------------------------------------------------\n"
    prompt_choice 7 || return 0
    case "$CHOICE" in
      1) masq_apply default ;;
      2) masq_apply minimal ;;
      3) masq_apply blog ;;
      4) masq_apply docs ;;
      5)
        local d; d=$(prompt "Path to local directory" "/var/www/html")
        masq_apply custom-dir "$d"
        ;;
      6)
        local u; u=$(prompt "Remote URL (e.g. https://example.org)" "")
        [[ -z "$u" ]] && { log_warn "aborted"; continue; }
        masq_apply custom-url "" "$u"
        ;;
      7) masq_preview ;;
      0) return 0 ;;
    esac
    printf "\n"
  done
}