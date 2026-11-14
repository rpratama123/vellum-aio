# Upstream changes

The build inserts the loopback hostname in the single `Bun.serve` listener in `gateway/src/index.ts` and fails if the insertion does not match exactly once. The local gateway remains available to the console and the bundled nginx process.

The AIO adapter calls upstream `buildIngressNginxConfig` and `buildRemoteWebIndexHtml` and changes the listen address from loopback to the container interface. It places nginx temporary directories under `/run/vellum` for the unprivileged process. The original route restrictions, edge headers, relative redirects, and streaming settings are carried through. The external ingress is TCP 7840.

## Firefox request bodies

The [web client patch](../patches/firefox-request-body.patch) makes the self-hosted request interceptor read the body with `Request.blob()` for methods that can carry one. Firefox can expose a null `Request.body` after the generated API client's request is copied, even when `blob()` still returns the original payload. The skipped read caused the daemon to receive empty chat, settings, and telemetry requests. The patch preserves Blob buffering for uploads and keeps GET and HEAD requests bodyless.
