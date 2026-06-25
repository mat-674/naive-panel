# naive-panel

CLI-панель для [naiveproxy](https://github.com/klzgrad/naiveproxy) — прокси-сервера на базе Caddy с плагином `forwardproxy@naive`. По стилю похоже на 3x-ui: одно текстовое меню, выбор цифрой, повседневная работа через алиас `naive`.

## Что умеет

- **Одна команда устанавливает всё:** Go → xcaddy → сборка Caddy с `forwardproxy@naive` → systemd unit → firewall → acme.sh → первый пользователь.
- **TLS:** Let's Encrypt HTTP-01 через acme.sh (домен должен указывать прямо на сервер, не за Cloudflare-proxy).
- **Пользователи:** создать / удалить / переименовать / сбросить пароль. Пароли в `/etc/naive/users.json` (chmod 600).
- **Шаринг credentials:**
  - одиночный URI `https://user:pass@host:443#name`
  - base64-список URI
  - **naive-клиент JSON** (`{"listen":"socks://127.0.0.1:1080","proxy":"https://user:pass@host"}`) — конфиг для бинарника `naive` от klzgrad
  - QR-код в терминале (qrencode) + PNG в `/tmp`
- **Маскарад:** 4 встроенных шаблона (default/minimal/blog/docs) + custom local dir + custom remote URL (reverse-proxy pass-through).
- **Трафик:** обёртка над `vnstat` — summary / daily / hourly / top / live / JSON dump. Считается **весь сервер** целиком по сетевым интерфейсам.
- **Управление сервисом:** restart / reload (zero-downtime через admin socket) / tail логов.

## Требования

- Ubuntu 22.04+ или Debian 12+
- Root-доступ
- Домен, указывающий A-записью на IP сервера (для TLS)
- Открытые порты 80/tcp и 443/tcp

## Установка

```bash
curl -fsSL https://raw.githubusercontent.com/mat-674/naive-panel/main/install.sh | sudo bash
```

После установки запустите интерактивный сетап:

```bash
sudo naive install
```

Он спросит:
1. Домен и email для LE
2. Шаблон маскарада
3. Имя и пароль первого пользователя

После — `sudo naive` откроет главное меню.

## Использование

```
=============================================================
  Naive-Panel  v0.1.0   server: proxy.example.com  mode: domain
=============================================================
  1. Users
  2. Masquerade site
  3. TLS / certificates
  4. Traffic statistics
  5. Restart Caddy
  6. Reload Caddy
  7. View access log
  8. View Caddy service log
  9. Show connection details
 10. Update Caddy (rebuild via xcaddy)
 11. Update panel
 12. Uninstall
  0. Exit
```

Подменю Users:

```
  1. Add user
  2. Delete user
  3. Rename user
  4. Reset password
  5. Show credentials for user
  6. Show connection URI for user
  7. Show QR code for user
  8. Show login+password string
  9. JSON subscription (naive-client config)
 10. base64 proxy list
  0. Back
```

## Клиент naive (от klzgrad)

Для подключения используется официальный клиент:

```bash
# Скачайте с https://github.com/klzgrad/naiveproxy/releases
./naive config.json
```

Где `config.json` имеет вид:

```json
{
  "listen": "socks://127.0.0.1:1080",
  "proxy":  "https://alice:p%40ssw0rd%21@proxy.example.com"
}
```

Меню `Users → 9. JSON subscription` выдаёт готовый файл — `single` для одного юзера или `all` (массив с разными SOCKS-портами 1080+).

## Файлы и пути

| Путь | Назначение |
|---|---|
| `/usr/local/bin/naive` | CLI-панель (этот скрипт) |
| `/usr/local/bin/caddy` | собранный Caddy с forwardproxy@naive |
| `/etc/naive/naive.conf` | конфиг (MODE, DOMAIN, EMAIL, ...) |
| `/etc/naive/users.json` | список пользователей (chmod 600) |
| `/etc/naive/caddy/caddy.json` | активный Caddy-конфиг |
| `/etc/naive/caddy/caddy.json.bak` | предыдущий валидный (для rollback) |
| `/etc/naive/masquerade/` | текущий маскирующий сайт |
| `/etc/systemd/system/naive-caddy.service` | systemd unit |
| `/etc/logrotate.d/naive` | ротация логов |
| `/var/log/naive/{access,error}.log` | логи |
| `/opt/acme.sh/` | acme.sh |
| `/opt/naive-panel/` | клон репозитория (для upgrade self) |

## Важно

- **Пароли в users.json — plaintext** (chmod 600). Это ограничение протокола HTTP basic auth, который не поддерживает хэши. Защищайте доступ к серверу.
- **Per-user учёт трафика невозможен** — naiveproxy-туннель (HTTP CONNECT) непрозрачен для Caddy, байты через туннель не видны. Используйте `vnstat` для учёта сервера целиком.
- **Домен не за Cloudflare-proxy** (orange cloud). HTTP-01 challenge должен видеть IP сервера напрямую. Используйте "DNS only" (grey cloud).
- **IP-режим не поддерживается** — TLS только через LE по домену.

## Обновление

```bash
sudo naive upgrade self    # git pull + пересборка /usr/local/bin/naive
sudo naive upgrade caddy   # пересборка caddy с актуальным forwardproxy@naive
```

## Удаление

```bash
sudo naive uninstall
```

Интерактивно спросит, что оставить (users, acme.sh, исходники).

## Документация

- [docs/install.md](docs/install.md) — детали установки
- [docs/users.md](docs/users.md) — управление пользователями
- [docs/traffic.md](docs/traffic.md) — учёт трафика
- [docs/subscriptions.md](docs/subscriptions.md) — форматы шаринга

## Лицензия

MIT