# Учёт трафика

## Что считается

`vnstat` — стандартный инструмент Linux, который ведёт БД в `/var/lib/vnstat/`. Обновляется раз в 5 минут (cron). Показывает трафик **по сетевому интерфейсу** для всего сервера.

```bash
sudo naive traffic   # открыть подменю
```

## Почему не per-user

Технически невозможно: naiveproxy использует HTTP CONNECT, и после handshake Caddy «пробрасывает» туннель opaque, не видя payload. Access-лог фиксирует только метаданные: кто (basicauth user), когда, сколько handshake-байт (≈ сотни), и код ответа. Реальный объём трафика юзера через access-лог **не получить**.

Если нужен честный per-user учёт — это другой класс инструментов (sing-box tun, marzban, etc.), и они ломают модель угроз naiveproxy (MITM termination на проксе).

## Подменю Traffic

| # | Команда | Что показывает |
|---|---|---|
| 1 | Summary | Общая сводка (5min/hour/day/month/etc) |
| 2 | Daily | По дням |
| 3 | Hourly | По часам |
| 4 | Top | Топ-дни по объёму |
| 5 | Live | Real-time (vnstat -l) |
| 6 | JSON | Дамп в JSON для скриптов |

## Ручной vnstat

`naive traffic` — обёртка; все данные доступны через `vnstat` напрямую:

```bash
vnstat -d           # daily
vnstat -h           # hourly
vnstat -t           # top
vnstat --json       # JSON dump
vnstat -l -i eth0   # live
```

## Где хранится

`/var/lib/vnstat/` — бинарная БД vnstat. Переживает ребуты. Сбрасывается вручную: `vnstat --remove -i eth0 && vnstat --add -i eth0`.

## Cron

`apt install vnstat` автоматически добавляет cron-задачу (раз в 5 минут). Если нет:

```bash
cat > /etc/cron.d/vnstat <<'EOF'
*/5 * * * * root /usr/sbin/vnstatc 2>&1 | logger -t vnstat
EOF
```