#!/bin/sh
set -e

CFG=/tmp/Caddyfile
cp /etc/caddy/Caddyfile.base "${CFG}"

if [ -n "${SECONDARY_APP_DOMAIN}" ]; then
  # Second app on the external `slotify` network.
  # Apex uses ordinary ACME; every subdomain uses on-demand TLS (same as YAKOSLOTS tenants).
  # SECONDARY_APP_UPSTREAM (host:port) overrides HOST + PORT. Default port is 3030.
  if [ -n "${SECONDARY_APP_UPSTREAM}" ]; then
    UPSTREAM="${SECONDARY_APP_UPSTREAM}"
  else
    if [ -z "${SECONDARY_APP_UPSTREAM_HOST}" ]; then
      echo "SECONDARY_APP_DOMAIN is set; set SECONDARY_APP_UPSTREAM_HOST or SECONDARY_APP_UPSTREAM=host:port." >&2
      exit 1
    fi
    UPSTREAM="${SECONDARY_APP_UPSTREAM_HOST}:${SECONDARY_APP_UPSTREAM_PORT:-3030}"
  fi

  cat >>"${CFG}" <<EOF

# Second application (${SECONDARY_APP_DOMAIN} and *.${SECONDARY_APP_DOMAIN} → ${UPSTREAM})
${SECONDARY_APP_DOMAIN} {
	encode zstd gzip
	reverse_proxy ${UPSTREAM}
}

*.${SECONDARY_APP_DOMAIN} {
	tls {
		on_demand
	}
	encode zstd gzip
	reverse_proxy ${UPSTREAM}
}
EOF
fi

# Deploy hooks. Caddyfile.prod stays the YAKOSLOTS base; this block is appended
# the same way as the second app. The hostname is fixed.
#
# Caddy is on the Docker bridge, so 127.0.0.1 in this process is the container.
# deploy-hooks-loopback shares the VPS network namespace and copies bytes
# between the unix socket below and the host's 127.0.0.1:9088. It does not
# parse HTTP.
#
# TLS matches the other explicit public hosts (apex / api / admin): automatic
# HTTPS via Let's Encrypt HTTP-01 and TLS-ALPN-01, email from {$ACME_EMAIL}.
# This is not on_demand TLS. A public certificate is issued only when
# deploy-hooks.internal.yakoslots.online has public DNS pointed at this VPS.
# This gateway has no DNS-01 provider, so a private-only name cannot get one.
#
# request_buffers is intentionally unset so the body is streamed, not read
# into a buffer first. No header is deleted: reverse_proxy forwards every
# non-hop-by-hop request header, including every name that starts with webhook-.
# lb_retries 0 keeps Caddy from buffering the body for a replay.
cat >>"${CFG}" <<'EOF'

# deploy-hooks.internal.yakoslots.online → VPS loopback 127.0.0.1:9088
deploy-hooks.internal.yakoslots.online {
	reverse_proxy unix//run/deploy-hooks/hooks.sock {
		header_up Host {http.request.host}
		flush_interval -1
		lb_retries 0
		transport http {
			versions 1.1
			compression off
		}
	}
}
EOF

exec caddy run --config "${CFG}" --adapter caddyfile
