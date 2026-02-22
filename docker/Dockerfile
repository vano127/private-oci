FROM alpine:3.19 AS base

# Add zscaler certificate for corporate proxy
COPY zscaler.crt /usr/local/share/ca-certificates/zscaler.crt
RUN cat /usr/local/share/ca-certificates/zscaler.crt >> /etc/ssl/certs/ca-certificates.crt

# Install xxd for hex encoding
RUN apk add --no-cache xxd

# Copy mtg binary from official image
COPY --from=nineseconds/mtg:2 /mtg /mtg

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Default port (can be overridden via MTG_PORT env var)
EXPOSE 3128

ENTRYPOINT ["/entrypoint.sh"]
