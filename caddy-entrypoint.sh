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

exec caddy run --config "${CFG}" --adapter caddyfile
