# Host gateway (Caddy)

Shared edge reverse proxy for Slotify (and optional second apps) on a single VPS.  
This directory is its **own Compose project** — not started by `deploy/deploy.sh`.  
Full specification: [`project.md`](project.md).

## Layout

| File | Purpose |
|------|---------|
| `docker-compose.yaml` | Production Caddy (`80` / `443` / `8080`) and the deploy-hooks loopback relay |
| `docker-compose.dev.yaml` | Local dev HTTP gateway |
| `Caddyfile.prod` | Production routing (`YAKOSLOTS_DOMAIN`); not edited for a second app |
| `project.md` | Gateway specification |
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

A second app has its own Compose file and joins the existing Docker network `slotify` (`external: true`, `name: slotify`). It does not change YAKOSLOTS routes in `Caddyfile.prod`.

When `SECONDARY_APP_DOMAIN` is set, `caddy-entrypoint.sh` appends two site blocks to the same upstream:

- `{SECONDARY_APP_DOMAIN}` — ordinary ACME for the apex
- `*.{SECONDARY_APP_DOMAIN}` — TLS `on_demand` (same pattern as YAKOSLOTS tenant subdomains)

Upstream address: `SECONDARY_APP_UPSTREAM` (`host:port`) when that variable is set; otherwise `SECONDARY_APP_UPSTREAM_HOST`:`SECONDARY_APP_UPSTREAM_PORT` (port default **3030**).

```env
SECONDARY_APP_DOMAIN=other.example.com
SECONDARY_APP_UPSTREAM_HOST=other-app
SECONDARY_APP_UPSTREAM_PORT=3030
```

The service must listen on `0.0.0.0:<port>` inside its container. Point DNS A/AAAA for the apex and `*.{apex}` at this VPS, then `./scripts/up.sh`.

## Deploy hooks

`deploy-hooks.internal.yakoslots.online` is appended by `caddy-entrypoint.sh`. `Caddyfile.prod` and the second-app blocks are unchanged. There is no `.env` key for this host.

Caddy is on the `slotify` bridge, so `127.0.0.1` inside that container is not the VPS. `deploy-hooks-loopback` (`network_mode: host`, image `alpine/socat:1.8.1.3`) listens on a unix socket in the `deploy_hooks_proxy` volume and copies bytes to **`127.0.0.1:9088` on the VPS**. It does not publish a TCP port. The webhook listener must bind the host loopback, not an address inside a container.

The proxy streams the request body (`request_buffers` is not set, `lb_retries` is 0) and does not delete request headers. Every non-hop-by-hop header is forwarded, including every name that starts with `webhook-`. Caddy's HTTP stack writes header names in canonical form (`Webhook-Id`).

TLS is automatic HTTPS, the same path as `api.` and `admin.`: Let's Encrypt HTTP-01 and TLS-ALPN-01 with `ACME_EMAIL`. It is not on-demand TLS. The label `internal` is not the special-use `.internal` TLD, so a public CA may issue for this name **only when it has a public A/AAAA record aimed at this VPS**. This gateway has no DNS-01 provider. A name that exists only in private DNS cannot get a public certificate; other sites keep theirs.

```bash
# listener on the VPS, bound to loopback only
# DNS: deploy-hooks.internal.yakoslots.online → this VPS
./scripts/up.sh
```

`./scripts/up.sh dev` does not start the loopback relay.
