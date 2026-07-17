FROM caddy:2.10.2-alpine

# The public gateway has only route configuration: application credentials stay
# in the backend Container App secrets, never in this image.
RUN addgroup -S -g 10001 simplegateway \
    && adduser -S -D -H -u 10001 -G simplegateway simplegateway \
    && chown -R simplegateway:simplegateway /config /data /etc/caddy

COPY --chown=simplegateway:simplegateway Caddyfile /etc/caddy/Caddyfile

USER 10001
