FROM docker.io/oven/bun:1.3.11@sha256:0733e50325078969732ebe3b15ce4c4be5082f18c4ac1a0f0ca4839c2e4e42a7 AS bun
FROM docker.io/qdrant/qdrant:v1.13.2@sha256:3042e5b0d9bb89c8a4ba26f93a6d9fa1991e6f7090b81f634c263a1223dd693b AS qdrant
FROM docker.io/library/debian:trixie-slim@sha256:4ffb3a1511099754cddc70eb1b12e50ffdb67619aa0ab6c13fcd800a78ef7c7a AS base

# Debian's signed repository snapshot fixes package resolution across builds.
RUN rm -f /etc/apt/sources.list.d/debian.sources && \
    printf '%s\n' 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/20261114T000000Z/ trixie main' \
    > /etc/apt/sources.list && \
    printf '%s\n' 'Acquire::Retries "3";' > /etc/apt/apt.conf.d/80-vellum

FROM base AS builder
COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git nodejs && rm -rf /var/lib/apt/lists/*
COPY versions.env /tmp/versions.env
WORKDIR /opt/vellum
RUN set -eu; . /tmp/versions.env; \
    git init -q && git fetch -q --depth=1 https://github.com/vellum-ai/vellum-assistant.git "$VELLUM_SHA" && \
    git checkout -q --detach FETCH_HEAD && test "$(git rev-parse HEAD)" = "$VELLUM_SHA" && \
    test "$(bun --version)" = "$BUN_VERSION" && \
    printf '%s  bun.lock\n' "$BUN_LOCK_SHA" | sha256sum -c - && \
    rm -rf .git
RUN bun install --frozen-lockfile --ignore-scripts --filter='./cli' --filter='./assistant' --filter='./assistant/src/api' \
      --filter='./gateway' --filter='./credential-executor' --filter='./clients/web' && \
    bun run meta/sync-bundled-copies.ts --plugins-only && \
    bun run assistant/scripts/generate-bundled-plugin-packages.ts
WORKDIR /opt/vellum/clients/web
RUN bun run openapi-ts && VITE_PLATFORM_MODE=false VITE_APP_VERSION=0.12.7 bun run build
WORKDIR /opt/vellum
RUN test -e gateway/node_modules/@vellumai/service-contracts/package.json && sed -i '/^    port: config.port,$/i\    hostname: "127.0.0.1",' gateway/src/index.ts && \
    test "$(grep -c 'hostname: "127.0.0.1"' gateway/src/index.ts)" -eq 1 && \
    rm -rf clients/web/node_modules clients/web/src clients/web/public

FROM base
LABEL org.opencontainers.image.title="Vellum AIO" \
      org.opencontainers.image.version="0.12.7" \
      org.opencontainers.image.description="Vellum Assistant in one container for Unraid" \
      io.vellum-aio.upstream-revision="25875c100149cc3c1f04d4acc3b77aca64531a83"
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq nginx python3 sqlite3 tzdata util-linux libgcc-s1 libstdc++6 libunwind8 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 1001 vellum && useradd --uid 1001 --gid 1001 --home-dir /data/home vellum \
    && ln -s bun /usr/local/bin/bunx
COPY --from=builder /usr/local/bin/bun /usr/local/bin/bun
COPY --from=qdrant /qdrant/qdrant /usr/local/bin/qdrant
COPY --from=builder /opt/vellum /opt/vellum
COPY versions.env /opt/vellum/aio/versions.env
COPY docker/entrypoint docker/vellum-aio /usr/local/bin/
COPY docker/supervise.py docker/qdrant.yaml docker/setup.ts docker/ingress.ts /opt/vellum/aio/
ENV HOME=/data/home XDG_CONFIG_HOME=/data/home/.config XDG_DATA_HOME=/data/home/.local/share \
    XDG_STATE_HOME=/data/home/.local/state XDG_CACHE_HOME=/data/home/.cache \
    VELLUM_ENVIRONMENT=production VELLUM_CLOUD=local VELLUM_DISABLE_PLATFORM=1 \
    APP_VERSION=0.12.7 RUNTIME_HTTP_HOST=127.0.0.1 RUNTIME_HTTP_PORT=7821 GATEWAY_PORT=7830 \
    RUNTIME_PROXY_REQUIRE_AUTH=true QDRANT_URL=http://127.0.0.1:6333 \
    CES_BOOTSTRAP_SOCKET_DIR=/run/vellum/ipc GATEWAY_IPC_SOCKET_DIR=/run/vellum/ipc \
    ASSISTANT_IPC_SOCKET_DIR=/run/vellum/ipc TZ=Asia/Jakarta
EXPOSE 7840/tcp
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s CMD ["/usr/local/bin/vellum-aio", "health"]
ENTRYPOINT ["/usr/local/bin/entrypoint"]
