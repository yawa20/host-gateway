# Host gateway (Caddy)

Shared edge reverse proxy for Slotify (and optional second apps) on a single VPS.  
This directory is its **own Compose project** — not started by `deploy/deploy.sh`.

## Layout

| File | Purpose |
|------|---------|
| `docker-compose.yaml` | Production Caddy (`80` / `443` / `8080`) |
| `docker-compose.dev.yaml` | Local dev HTTP gateway |
| `Caddyfile.prod` | Production routing (`YAKOSLOTS_DOMAIN`) |
| `Caddyfile.dev` | Local `*.slotify.localhost:8080` routing |
| `.env` | Gateway-only secrets (copy from `.env.example`) |
| `scripts/up.sh` / `down.sh` | Start / stop |
| `scripts/ensure-network.sh` | Verify Docker network exists |

## Docker network

Production app stack ([`docker-compose.prod.yaml`](../docker-compose.prod.yaml)) creates a bridge network named **`slotify`**.  
Gateway compose declares it as `external: true` and **does not** create it.

**Start order**

1. App stack (`/opt/slotify`) — `./deploy/deploy.sh`
2. Gateway (`/opt/host-gateway` or `host-gateway/` in the same clone) — `./scripts/up.sh`

`scripts/ensure-network.sh` fails fast if `slotify` is missing.

Local dev: root [`docker-compose.yaml`](../docker-compose.yaml) also attaches services to a network named `slotify` so the dev gateway can join the same name.

## VPS paths

| Path | Role |
|------|------|
| `/opt/slotify` | Git checkout; app `.env`; `./deploy/deploy.sh` |
| `/opt/host-gateway` | Gateway checkout **or** `cd /opt/slotify/host-gateway` with `.env` here |

Recommended: one Origin clone at `/opt/slotify`, gateway operated from `/opt/slotify/host-gateway` (no second clone required).

```bash
# App
cd /opt/slotify
cp deploy/env.prod.example .env   # edit — Symfony / Next build vars only
./deploy/deploy.sh origin/main

# Gateway (after app stack is up)
cd /opt/slotify/host-gateway
cp .env.example .env              # YAKOSLOTS_DOMAIN, ACME_EMAIL, …
./scripts/up.sh
```

Separate clone:

```bash
git clone <origin-url> /opt/host-gateway
cd /opt/host-gateway/host-gateway   # monorepo layout
cp .env.example .env
./scripts/up.sh
```

## Local development

```bash
# Terminal 1 — app
docker compose up -d

# Terminal 2 — gateway
cd host-gateway
cp .env.example .env
# set SLOTIFY_REPO_ROOT=/absolute/path/to/slotify clone
./scripts/up.sh dev
```

Open [http://slotify.localhost:8080](http://slotify.localhost:8080) (see [`apps/README.md`](../apps/README.md)).  
Without Docker: [`scripts/local-gateway.mjs`](../scripts/local-gateway.mjs).

## Migration from `docker/gateway/` (in-repo gateway)

1. Add `YAKOSLOTS_DOMAIN` to **host-gateway** `.env` (same apex as `BASE_DOMAIN` in app `.env`).
2. Deploy app only: `./deploy/deploy.sh` (no Caddy in app compose).
3. Remove old in-app gateway container if it still runs:  
   `docker compose -f docker-compose.prod.yaml stop gateway 2>/dev/null; docker compose -f docker-compose.prod.yaml rm -f gateway 2>/dev/null || true`
4. `./scripts/up.sh` from this directory.
5. TLS volumes move to the `slotify-gateway` compose project; first start may re-issue certificates.

## Secondary application

Set `SECONDARY_APP_DOMAIN` and `SECONDARY_APP_UPSTREAM` in `.env`. The upstream container must join network `slotify`.# host-gateway
