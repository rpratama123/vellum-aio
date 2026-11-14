# Vellum 0.12.7 source audit

[Release v0.12.7](https://github.com/vellum-ai/vellum-assistant/releases/tag/v0.12.7) resolves to [25875c100149cc3c1f04d4acc3b77aca64531a83](https://github.com/vellum-ai/vellum-assistant/tree/25875c100149cc3c1f04d4acc3b77aca64531a83). `cli/package.json` and `clients/web/package.json` report 0.12.7. Upstream `.tool-versions` specifies Bun 1.3.11. The image checks the Git commit, Bun version and `bun.lock` SHA-256.

| Source at the pinned commit | Runtime contract |
| --- | --- |
| `cli/src/commands/hatch.ts`, `cli/src/lib/hatch-local.ts` | Local hatch allocates resources and uses an initial workspace config overlay, a shared signing key and a separate guardian bootstrap secret. It starts CES and the daemon, then the gateway, then leases the guardian token and configures credentials. Docker mode starts sibling containers. |
| `cli/src/lib/local.ts`, `cli/src/commands/wake.ts` | Local launch uses detached child processes, PID files and per-instance workspace, security and port overrides. Wake reuses the key embedded in the lockfile. An explicit guardian repair can revoke existing credentials. |
| `cli/src/lib/assistant-config.ts`, `packages/local-mode/src/config.ts` | Production Linux uses `$HOME/.vellum.lock.json` with `activeAssistant` and a per-instance entry. Guardian tokens use `$XDG_CONFIG_HOME/vellum/assistants/<id>/guardian-token.json`. |
| `cli/src/lib/guardian-token.ts`, `gateway/src/http/routes/channel-verification-session-proxy.ts` | `leaseGuardianToken` posts to loopback `/v1/guardian/init` and persists the result. The gateway guards the lease using `guardian-init.lock` and `guardian-init-consumed.json` in its security directory. |
| `gateway/src/auth/token-service.ts`, `assistant/src/runtime/auth/token-service.ts` | Local mode injects the same 32-byte hex `ACTOR_TOKEN_SIGNING_KEY` into both services. The assistant synchronizes a raw copy to `workspace/deprecated/actor-token-signing-key`. The Docker signing-key bootstrap described in the plan is bypassed in this topology. The separate single-use guardian guard still applies. |
| `assistant/src/daemon/main.ts`, `assistant/src/runtime/http-server.ts` | Foreground daemon, TCP 7821 on loopback, `/readyz` JSON readiness. `VELLUM_WORKSPACE_DIR` relocates the workspace and its `data/db/assistant.db`, WAL, settings, prompts, logs and memory. |
| `gateway/src/index.ts`, `gateway/src/db/connection.ts` | Foreground gateway, TCP 7830, `RUNTIME_PROXY_REQUIRE_AUTH=true`. `/readyz` may send HTTP 200 with `ready:false`. Gateway identity and trust tables persist in `GATEWAY_SECURITY_DIR/gateway.sqlite`. |
| `credential-executor/src/main.ts`, `credential-executor/src/paths.ts` | Local CES uses `CES_BOOTSTRAP_SOCKET_DIR/ces.sock` without a TCP listener. Local credentials are `CREDENTIAL_SECURITY_DIR/{keys.enc,store.key}`. Gateway and assistant IPC use `GATEWAY_IPC_SOCKET_DIR` and `ASSISTANT_IPC_SOCKET_DIR`. |
| `assistant/src/plugins/defaults/memory/startup.ts`, `assistant/src/persistence/embeddings/qdrant-manager.ts` | Memory starts Qdrant asynchronously. The built-in downloader targets 1.13.2. Setting `QDRANT_URL` skips the downloader. AIO provides the same version as a supervised process on loopback TCP 6333. |
| `cli/src/lib/provider-secrets.ts`, `assistant/src/config/loader.ts` | Hidden terminal input is supported. Authenticated `/v1/secrets` writes provider credentials. The initial config overlay seeds the selected provider/model and is consumed by the daemon. Custom endpoint providers are not in the upstream fixed-model hatch list. |
| `cli/src/commands/pair.ts`, `cli/src/commands/connect.ts` | `pair --url`, `--app`, `--web-approve` and `connect import` exist. The host mints locally and advertises an HTTPS origin separately. |
| `cli/src/lib/nginx-ingress.ts`, `clients/web/vite.config.ts` | The gateway alone cannot serve the remote SPA. Upstream renders nginx routes and remote config, and the frontend is built under `/assistant/`. Its edge excludes local-only token, guardian, and pairing management routes. |

```text
first boot → SETUP_REQUIRED → console setup → supervised backend
           → guardian lease + credential verification → start ingress → READY
later boot → validate lockfile, guardian, keys and databases → same services → READY
interrupted hatch / missing state → NEEDS_REPAIR
```

The AIO entrypoint owns foreground children for the entire container lifetime. The upstream CLI is used for state and auth primitives, and process management stays in the AIO supervisor. The inherited HOME and XDG paths live under `/data/home`, which also contains the fixed per-instance directory. Unix sockets and the rendered nginx configuration live under `/run/vellum`.
