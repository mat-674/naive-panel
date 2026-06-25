# Управление пользователями

## Где хранятся

`/etc/naive/users.json` (chmod 600):

```json
{
  "version": 1,
  "users": [
    {"name":"alice","pass":"...","created":1750000000,"updated":1750000000},
    {"name":"bob","pass":"...","created":1750000000,"updated":1750000000}
  ]
}
```

## Имена пользователей

- Только `[a-z0-9_-]`, до 32 символов
- Не могут начинаться с дефиса
- Должны быть уникальны (операции над дубликатом падают с ошибкой)

## Операции (главное меню → Users)

| # | Операция | Поведение |
|---|---|---|
| 1 | Add | Создаёт юзера с заданным или случайным паролем (20 символов) |
| 2 | Delete | Удаляет; caddy перезагружается с новым конфигом |
| 3 | Rename | Меняет имя; все существующие URI старого имени перестают работать |
| 4 | Reset password | Новый случайный или заданный пароль |
| 5 | Show credentials | Печатает user и pass открытым текстом |
| 6 | Show URI | Печатает `https://user:pass@host:443#name` |
| 7 | Show QR | QR-код в терминале + PNG в /tmp/naive-qr-NAME.png |
| 8 | Show login+pass | Одна строка `user:pass` |
| 9 | JSON subscription | naive-клиент конфиг (один или массив всех) |
| 10 | base64 proxy list | Список URI в base64 |

## Безопасность

- Пароли — **plaintext** в users.json. Это ограничение протокола HTTP basic auth.
- Файл chmod 600, root:root.
- Защищайте shell-доступ к серверу.
- После удаления пользователя его пароль остаётся в `caddy.json.bak` (если вы не делали `naive uninstall`). Периодически очищайте: `rm /etc/naive/caddy/caddy.json.bak` после успешного reload.

## Автоматизация (без TTY)

Все операции можно запускать скриптом:

```bash
naive users add alice 'MyStr0ng!Pass'
naive users delete alice
naive users rename alice alice2
naive users reset-pass alice 'NewStr0ng!Pass'
```

(Для скриптового режима планируется `naive users <subcommand>` — пока используйте JSON-файл напрямую + `systemctl reload naive-caddy`.)

## Что делает каждая мутация

1. `flock /var/lock/naive.lock` (защита от гонок)
2. Изменяет `users.json` атомарно (tmp + mv)
3. Перерендерит `caddy.json`
4. `caddy validate` (если caddy в PATH)
5. `caddy reload` через admin socket (zero-downtime)
6. При ошибке валидации — откат на `caddy.json.bak` + restart