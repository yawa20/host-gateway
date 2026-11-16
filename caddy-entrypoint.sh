#!/bin/sh
set -e

CFG=/tmp/Caddyfile
cp /etc/caddy/Caddyfile.base "${CFG}"

if [ -n "${SECONDARY_APP_DOMAIN}" ]; then
  # Optional second apex — upstream must join the external `slotify` network.
  cat >>"${CFG}" <<EOF

# Second application (SECONDARY_APP_DOMAIN / SECONDARY_APP_UPSTREAM)
${SECONDARY_APP_DOMAIN} {
	encode zstd gzip
	reverse_proxy ${SECONDARY_APP_UPSTREAM}
}
EOF
fi

exec caddy run --config "${CFG}" --adapter caddyfile