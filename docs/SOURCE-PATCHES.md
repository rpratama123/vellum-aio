# Upstream changes

The build inserts the loopback hostname in the single `Bun.serve` listener in `gateway/src/index.ts` and fails if the insertion does not match exactly once. The local gateway remains available to the console and the bundled nginx process.

The AIO adapter calls upstream `buildIngressNginxConfig` and `buildRemoteWebIndexHtml` and changes the listen address from loopback to the container interface. It places nginx temporary directories under `/run/vellum` for the unprivileged process. The original route restrictions, edge headers, relative redirects, and streaming settings are carried through. The external ingress is TCP 7840.
