# Host gateway (Caddy) — спецификация

Канонический код: репозиторий [`yawa20/host-gateway`](https://cursor.com/codebase/yawa20/host-gateway).  
На VPS: `/opt/host-gateway` (отдельный clone; не внутри `slotify`).  
Compose-проект: **`slotify-gateway`**, сервис **`gateway`** (образ `caddy:2.9-alpine`).

Цель: один edge на VPS — TLS и маршрутизация по `Host` в контейнеры app-стека и опционально в другие приложения в той же Docker-сети. **Деплой Symfony/Next и healthcheck PHP — не зона ответственности gateway.**

## Связка с app-стеком

| Элемент | Где |
|--------|-----|
| App-стек Slotify | `/opt/slotify`, `docker-compose.prod.yaml`, проект `slotify-prod` |
| Сеть Docker | **`slotify`** (bridge, фиксированное имя в app compose) |
| Gateway | подключается к `slotify` как **`external: true`**, сеть **не создаёт** |
| Старт | 1) `./deploy/deploy.sh` (создаёт сеть и контейнеры), 2) `cd /opt/host-gateway && ./scripts/up.sh` |

`scripts/ensure-network.sh` завершается с ошибкой, если сети `slotify` нет.

Имена upstream в Caddy — **Compose service names** в app-стеке (`php`, `web-client`, `platform-admin`, `tenant`), DNS Docker внутри сети `slotify`.

## Порты на хосте (gateway)

| Порт | Назначение |
|------|------------|
| **80** / **443** | Публичный HTTP(S); catch-all по IP для default tenant (см. ниже) |
| **8080** | Platform admin по IP и по `http://{YAKOSLOTS_DOMAIN}:8080` (маркетинговый apex на :8080 **не** отдаётся) |

Порты **не** проксируют Postgres/RabbitMQ/app-порты наружу — только Caddy.

## Переменные окружения (`host-gateway/.env`)

Секреты только в `.env` на сервере, в репозиторий не коммитить.

| Переменная | Обязательна | Назначение |
|------------|-------------|------------|
| `YAKOSLOTS_DOMAIN` | да (prod) | Apex продукта (например `yakoslots.com`). Должен совпадать с `BASE_DOMAIN` в `/opt/slotify/.env` |
| `ACME_EMAIL` | да | Email для Let's Encrypt |
| `SLOTIFY_NETWORK_NAME` | нет (default `slotify`) | Имя external network |
| `SECONDARY_APP_DOMAIN` | нет | Apex **другого** приложения; если пусто — маршруты второго приложения не добавляются |
| `SECONDARY_APP_UPSTREAM_HOST` | если включён secondary | Имя сервиса второго compose в сети `slotify` |
| `SECONDARY_APP_UPSTREAM_PORT` | нет (default **3030**) | Порт upstream внутри контейнера |
| `SECONDARY_APP_UPSTREAM` | нет | Полная подстановка `host:port`; если задана — перекрывает HOST+PORT |

Локальная разработка: `SLOTIFY_REPO_ROOT`, `docker-compose.dev.yaml`, `./scripts/up.sh dev` — вне prod-спеки ниже.

## Сборка конфига Caddy

1. **`Caddyfile.prod`** монтируется как `/etc/caddy/Caddyfile.base` — маршрутизация **YAKOSLOTS**.
2. **`caddy-entrypoint.sh`** копирует base в `/tmp/Caddyfile` и при `SECONDARY_APP_DOMAIN` **дописывает** блоки apex + `*.{domain}` → `reverse_proxy` на upstream второго приложения.
3. Запуск: `caddy run --config /tmp/Caddyfile`.

Правки маршрутизации YAKOSLOTS — в `Caddyfile.prod` + перезапуск gateway. Второе приложение — в `.env` + перезапуск (без правки base, если достаточно entrypoint).

## Маршрутизация YAKOSLOTS (без изменений при добавлении secondary)

Плейсхолдер `{$YAKOSLOTS_DOMAIN}` подставляется из env compose.

| Запрос (Host / порт) | Upstream | Примечание |
|----------------------|----------|------------|
| `https://{apex}` | `web-client:3000`; `path /api/*` → `php:8000` | Маркетинг |
| `https://api.{apex}` | `php:8000` | JSON API |
| `https://admin.{apex}` | `platform-admin:3001` | Суперадмин |
| `https://{slug}.{apex}` | `tenant:3002`; `/api/*` → `php:8000` | Tenant; TLS **on_demand** |
| `http(s)://{apex}:8080`, `:8080` (прочие Host) | `platform-admin:3001`; `/api/*` → `php` | Админка без маркетинга на :8080 |
| `:80`, `:443`, Host = IP или без совпадения с блоками выше | `tenant:3002`; `/api/*` → `php` | Default tenant по IP |

Ограничения (как в репозитории):

- Stock Caddy — **без** `host_regexp` и сторонних matcher-плагинов.
- Глобальный **`on_demand_tls`** с `ask http://php:8000/api/health` (временно allow-all; ужесточать перед широким wildcard).
- HTTPS на голый IP — не HTTP-01 LE; для IP предпочтителен HTTP :80.

`./deploy/deploy.sh` **не** поднимает и **не** перезапускает gateway.

## Второе приложение на той же сети

Не меняет таблицу YAKOSLOTS. Условия:

1. Отдельный `docker-compose` с `networks.slotify.external: true`, `name: slotify`.
2. Сервис слушает **`0.0.0.0:<port>`** внутри контейнера (ожидаемый default в gateway — **3030**).
3. DNS: **A/AAAA** на apex и **`*.{apex}`** второго домена → тот же VPS.
4. В `host-gateway/.env`: `SECONDARY_APP_DOMAIN`, `SECONDARY_APP_UPSTREAM_HOST`, `SECONDARY_APP_UPSTREAM_PORT` (или `SECONDARY_APP_UPSTREAM`).
5. `./scripts/up.sh`.

Поведение entrypoint (целевая спека):

- Сайт **`{SECONDARY_APP_DOMAIN}`** → reverse_proxy на upstream (обычный ACME для apex).
- Сайт **`*.{SECONDARY_APP_DOMAIN}`** → тот же upstream, TLS **`on_demand`** (как tenant subdomains YAKOSLOTS).

Пример compose для второго app: `yawa20/slotify` → `deploy/secondary-app.compose.example.yaml`. Операторская выжимка также в `slotify` → `docs/deploy.md` § «Second application».

## TLS и тома

- Тома `caddy_data`, `caddy_config` — в compose-проекте **slotify-gateway** (не в app-стеке).
- После миграции gateway из in-repo Caddy первый старт может перевыпустить сертификаты.

## Миграция сети `slotify-prod_slotify`

Старые деплои использовали сеть `slotify-prod_slotify`. Текущий app compose фиксирует имя **`slotify`**. При ошибках «container … is not connected to network slotify-prod_slotify» — `slotify` → `./deploy/fix-legacy-network.sh`, затем `./deploy/deploy.sh`. Gateway после этого остаётся на external `slotify`.

## Чеклист оператора

1. App healthy (`php` healthcheck, сеть `slotify` у `php` и `database`).
2. `YAKOSLOTS_DOMAIN` = `BASE_DOMAIN`; DNS для prod-домена YAKOSLOTS.
3. Gateway `.env` заполнен; `./scripts/up.sh`.
4. Опционально второй домен: secondary compose + `SECONDARY_APP_*` + DNS + перезапуск gateway.

## Связанные артефакты

| Документ / путь | Содержание |
|-----------------|------------|
| `README.md` | Краткий runbook |
| `yawa20/slotify` `docs/deploy.md` | VPS, DNS, second app |
| `caddy-entrypoint.sh`, `.env.example` | Второе приложение: apex и `*.{domain}`, порт upstream по умолчанию 3030 |
| Project store `internal/php-healthcheck.md` | Почему `php` должен быть healthy до зависимых сервисов |
