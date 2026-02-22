#!/bin/sh
set -e

# Required environment variables:
# - MTG_SECRET: base secret (16 bytes hex)
# - MTG_DOMAIN: fake-TLS domain (e.g., cdn.jsdelivr.net)
#
# Optional:
# - MTG_PORT: bind port (default: 3128)
# - MTG_ANTI_REPLAY: enable anti-replay (default: true)
# - MTG_BLOCKLIST: enable IP blocklist (default: true)

if [ -z "$MTG_SECRET" ]; then
    echo "ERROR: MTG_SECRET is required"
    exit 1
fi

if [ -z "$MTG_DOMAIN" ]; then
    echo "ERROR: MTG_DOMAIN is required"
    exit 1
fi

MTG_PORT="${MTG_PORT:-3128}"
MTG_ANTI_REPLAY="${MTG_ANTI_REPLAY:-true}"
MTG_BLOCKLIST="${MTG_BLOCKLIST:-true}"

# Generate fake-TLS secret: ee + base_secret + domain_hex
DOMAIN_HEX=$(echo -n "$MTG_DOMAIN" | xxd -p | tr -d '\n')
FAKE_TLS_SECRET="ee${MTG_SECRET}${DOMAIN_HEX}"

echo "Starting MTProxy"
echo "Domain: $MTG_DOMAIN"
echo "Port: $MTG_PORT"
echo "Anti-replay: $MTG_ANTI_REPLAY"
echo "Blocklist: $MTG_BLOCKLIST"

# Generate config file
cat > /tmp/mtg-config.toml << EOF
debug = true
secret = "$FAKE_TLS_SECRET"
bind-to = "0.0.0.0:$MTG_PORT"
domain-fronting-port = 443
tolerate-time-skewness = "5s"
allow-fallback-on-unknown-dc = true

[defense.anti-replay]
enabled = $MTG_ANTI_REPLAY
max-size = "1mib"
error-rate = 0.001

[defense.blocklist]
enabled = $MTG_BLOCKLIST
download-concurrency = 2
urls = [
    "https://iplists.firehol.org/files/firehol_level1.netset"
]
update-each = "24h"

[network.timeout]
tcp = "30s"
http = "30s"
idle = "5m"
EOF

# Run mtg
exec /mtg run /tmp/mtg-config.toml
