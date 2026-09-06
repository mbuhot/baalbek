# The PWA as it ships: nginx serving `web:build`'s `dist`, with `server`'s API
# reverse-proxied onto the same origin (src/api.ts calls its own origin).
#
# Build from web/, not from the repository root — everything the image needs is
# in this project:
#
#   docker build -f web/Dockerfile -t baalbek-web web
#
# or `moon run web:image`, which builds `dist` first.
#
# One serving stage, not a build stage plus a serving stage, unlike
# server/Dockerfile. That Dockerfile compiles inside the image because a BEAM
# release embeds absolute host paths and host-built NIFs. `dist` has neither —
# it is portable static output — and it is already a shipped artifact consumed
# by `mobile`'s Capacitor bundle, so building it a second time inside this
# image would be a second source of the same artifact, free to drift from the
# one `mobile` embeds. Moon's `deps` on the output-declaring `web:build` is
# what keeps it fresh. See web/README.md and
# ../e2e/spec/decisions/adr-0001-dockerized-e2e-stack.md.
#
# Configuration is by environment variable at container start:
#
#   SERVER_ORIGIN   default http://server:4004, the API this proxies to

FROM nginx:1.29-alpine

# nginx's entrypoint renders /etc/nginx/templates/*.template with envsubst. The
# filter keeps it to this one name, so nginx's own $host/$scheme survive.
ENV NGINX_ENVSUBST_FILTER="SERVER_ORIGIN" \
    SERVER_ORIGIN="http://server:4004"

COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY dist /usr/share/nginx/html

EXPOSE 80

# Static only: this reports "the shell is being served", never that the API
# behind the proxy is up.
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=12 \
    CMD wget -q -O /dev/null http://127.0.0.1/index.html
