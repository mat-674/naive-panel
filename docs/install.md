# Установка

## Шаг 1. Подготовка сервера

- Ubuntu 22.04+ / Debian 12+
- root-доступ
- A-запись для вашего домена указывает на IP сервера
- Порты 80/tcp и 443/tcp свободны и не заблокированы провайдером/ЦОД

## Шаг 2. Установка одной командой

```bash
curl -fsSL https://raw.githubusercontent.com/mat-674/naive-panel/refs/heads/master/install.sh | sudo bash
```

Что делает:
1. `apt install -y jq qrencode ufw curl git vnstat openssl`
2. `git clone https://github.com/mat-674/naive-panel /opt/naive-panel`
3. Склеивает `naive` + `lib/*.sh` → `/usr/local/bin/naive`
4. Устанавливает systemd unit и logrotate
5. Подсказывает следующий шаг

## Шаг 3. Интерактивный сетап

```bash
sudo naive install
```

Вам будет задано:

- **Domain** — например, `proxy.example.com`
- **Email** — для регистрации в Let's Encrypt
- **Masquerade** — что увидит посетитель, зашедший на `https://proxy.example.com/`:
  - default / minimal / blog / docs — встроенные шаблоны
  - custom local dir — путь к своей папке с HTML
  - custom remote URL — reverse_proxy на любой URL
- **Username + password** — первый пользователь

## Шаг 4. Установщик автоматически

1. Установит Go 1.22 (если в системе < 1.21)
2. Установит `xcaddy`
3. Соберёт Caddy с плагином `forwardproxy@naive` (3-10 минут)
4. Применит `setcap cap_net_bind_service=+ep /usr/local/bin/caddy`
5. Откроет порты 80 и 443 в ufw
6. Запустит `systemctl enable --now naive-caddy`
7. Запросит LE-сертификат через acme.sh HTTP-01
8. Покажет URI первого пользователя

## Cloudflare и HTTP-01

Если ваш домен за Cloudflare, **отключите проксирование** для записи `proxy.example.com`:
- В DNS-записях нажмите на оранжевое облако — оно должно стать серым (DNS only).
- Иначе ACME увидит IP Cloudflare, а не вашего сервера, и выпуск сертификата провалится.

## Проверка после установки

```bash
sudo systemctl status naive-caddy
sudo naive version
sudo naive info
```

Из локальной сети:

```bash
curl -I https://proxy.example.com
# Должен быть 200 OK с маскирующим сайтом
```

Через прокси:

```bash
# С клиента, где есть бинарник naive
./naive config.json
# В другом терминале:
curl -x socks5h://127.0.0.1:1080 https://example.com
```

## Переустановка

`naive install` идемпотентен для большинства шагов:
- Если caddy уже собран — пропустит
- Если acme.sh уже есть — пропустит
- Если пользователь уже существует — ошибка, но остальные шаги продолжатся

Для полного перезапуска сначала `naive uninstall`, потом `naive install`.