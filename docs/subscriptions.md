# Форматы шаринга credentials

Меню `Users` предлагает три способа поделиться credentials.

## 1. Одиночный URI

```
https://alice:p%40ssw0rd%21@proxy.example.com:443#alice
```

- Пароль URL-encoded
- Фрагмент `#alice` — отображаемое имя в клиенте
- Подходит для QR-кода, импорта в NekoBox / sing-box через «Add from clipboard»

## 2. base64-список URI

Список URI (по одному на строку), кодированный в base64:

```
echo -n 'https://alice:p%40ss@proxy.example.com:443#alice
https://bob:hunter2@proxy.example.com:443#bob' | base64 -w0
```

Используется в качестве subscription URL в клиентах, которые поддерживают pull-импорт списка.

## 3. naive-клиент JSON

Для бинарника `naive` от klzgrad:

```json
{
  "listen": "socks://127.0.0.1:1080",
  "proxy":  "https://alice:p%40ssw0rd%21@proxy.example.com:443"
}
```

- `listen` — локальный SOCKS/HTTP-сервер клиента
- `proxy` — URL сервера с credentials

Опциональные поля (для отладки):
- `"log": "naive.log"` — путь к лог-файлу клиента

### Для нескольких юзеров

`Users → 9. JSON subscription → 2. all` — массив:

```json
[
  {"listen":"socks://127.0.0.1:1080","proxy":"https://alice:p%40ss@proxy.example.com:443"},
  {"listen":"socks://127.0.0.1:1081","proxy":"https://bob:hunter2@proxy.example.com:443"}
]
```

Каждому юзеру выделяется свой SOCKS-порт (1080 + N). Запускать в нескольких терминалах или через process manager.

## QR-код

`Users → 7. Show QR code for user` — печатает QR в терминале (Unicode-блоки) + сохраняет PNG в `/tmp/naive-qr-NAME.png`. Сканируется камерой телефона, импортируется в NekoBox / NekoRay / sing-box for Android.

## Подключение клиента

### Linux / macOS

```bash
# Скачайте naive с https://github.com/klzgrad/naiveproxy/releases
chmod +x naive
./naive config.json
# → listens on socks5://127.0.0.1:1080

# В другом терминале:
curl -x socks5h://127.0.0.1:1080 https://example.com
```

### Android / iOS

sing-box / NekoRay / NekoBox — добавить через QR или вставить URI. Используйте фрагмент `#name` как display name.

### Windows

sing-box for Windows, NekoRay for Windows — то же самое.