# lib/qr.sh — обёртка над qrencode. Используется из users_menu.
# qrencode проверяется в qr_uri при вызове.

# qr_uri <name> — печатает QR-код для URI этого юзера в терминал
qr_uri() {
  require_cmd qrencode "install with: apt install qrencode"
  local name="$1" data pass uri
  data=$(users_get "$name") || die "user '$name' not found"
  pass=$(printf "%s" "$data" | jq -r .pass)
  uri=$(sub_uri "$name" "$pass")
  printf "URI: %s\n\n" "$uri"
  qrencode -t ANSIUTF8 -s 1 -m 2 "$uri"
  printf "\nPNG (для импорта): "
  local png="/tmp/naive-qr-$name.png"
  qrencode -t PNG -o "$png" "$uri" && echo "$png" || echo "PNG generation failed"
}

# qr_text <text> [out.png] — обёртка для произвольного текста
qr_text() {
  local text="$1" out="${2:-/tmp/naive-qr.png}"
  qrencode -t PNG -o "$out" "$text"
  echo "PNG: $out"
  qrencode -t ANSIUTF8 -s 1 -m 2 "$text"
}