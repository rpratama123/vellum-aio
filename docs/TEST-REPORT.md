# Vellum AIO 0.12.7 test report

2026-11-14. Local Fedora 45 workstation, Linux/amd64, rootless Podman, SELinux enabled. Upstream commit `25875c100149cc3c1f04d4acc3b77aca64531a83`. Tested image ID `sha256:6356c71c7a8461d98bc600c918acf0fb550513d5e1f4eb2532e8251eabcbb1fd`. Local manifest digest `sha256:4bd703015268959600cc97c8dd3e968a8bfa3552beaa7e88d9fcfdb177c0e480`.

```sh
scripts/static-checks.sh
CONTAINER_ENGINE=podman scripts/build-local.sh localhost/vellum-aio:0.12.7
CONTAINER_ENGINE=podman tests/lifecycle.sh localhost/vellum-aio:0.12.7
```

The lifecycle suite uses normal console onboarding, the upstream pairing CLI, real pairing and guardian routes, and a loopback OpenAI-compatible model fixture. Unraid MCP was used only for network inventory.

| ID | Result | Evidence |
| --- | --- | --- |
| T01 Clean boot | PASS | Docker health reports healthy in `SETUP_REQUIRED`. The ingress stays closed. |
| T02 Interactive hatch | PASS | A pseudo-terminal drove the console prompts. Guardian registration, a named assistant, keyed custom inference, and a separate keyless setup reached `READY`. Paid provider validation was outside this test. |
| T03 Duplicate setup | PASS | Existing identity caused setup to exit with “Setup is already complete.” |
| T04 Interrupted setup | PASS | Simulated interruption by staging the initial hatch file before the upstream lockfile existed. Restart preserved it and reported `NEEDS_REPAIR`. |
| T05 Ten restarts | PASS | The final image reached READY ten times with the same paired token. The suite also exercised stop/start. |
| T06 Container replacement | PASS | A clean container reopened the same bind, served the saved conversation and rotated the paired refresh token for the same guardian. |
| T07 Unraid reboot | NOT TESTED | Unraid access was read-only. |
| T08 Repeat bootstrap | PASS | Loopback guardian bootstrap with the same secret returned 403. Local-mode signing uses the persisted shared key. The Docker orchestration-specific signing-key exchange does not run in AIO. |
| T09 CES vault | PASS | After an additional container replacement, an authenticated secret lookup confirmed the saved credential was readable, and another chat received a streamed reply through the saved endpoint and profile. Paid-provider requests were outside this check. |
| T10 Databases and memory | PASS | Chat history and profile configuration persisted, workspace and gateway SQLite integrity checks passed, and persistent Qdrant collections reopened. Semantic recall quality was outside this check. |
| T11 Service crash | PASS | SIGKILL of Qdrant produced DEGRADED and a supervised restart. Existing paired access still worked. |
| T12 One container | PASS | One disposable Vellum container with processes owned by the local supervisor. No Docker socket or sibling Vellum containers. Local Caddy and the model fixture are test infrastructure. |
| T13 Native Unraid UI | NOT TESTED | `xmllint` and structural checks passed. Real template import, console and UI lifecycle need Unraid deployment. |
| T14 Existing Cloudflared | NOT TESTED | Read-only inventory confirmed a shared Docker network. Local Caddy resolved the replacement container by Docker DNS and reached the ingress over a user-defined bridge. |
| T15 Pairing web endpoints | PASS | Local Caddy HTTPS served the pairing page assets/config and API, including the device exchange and browser cookie refresh. Authenticated SSE delivered a heartbeat. Cloudflare hostname and interactive browser rendering were outside this check. |
| T16 Physical iOS/Windows | NOT TESTED | No physical clients were used. Local API test exercised device exchange, chat send/reply and a settings write. |
| T17 Cloudflared restart | NOT TESTED | The paired token authenticated after local Caddy restart. Live Cloudflared restart requires deployment. |
| T18 Missing appdata | PASS | A container started without the bind exited `NEEDS_REPAIR`. |
| T19 Corrupt data | PASS | Removed the vault key on a disposable restored copy. Restart preserved the remaining files, reported NEEDS_REPAIR and kept ingress closed. |
| T20 Backup and restore | PASS | Stopped the source, archived the bind with numeric ownership, and restored into a fresh bind. Existing paired access and chat history survived. |
| T21 Credentials | PASS | Redacted Gitleaks source scan reported zero findings. Image checks confirmed absence of mounted state, vault, guardian token, upstream Git metadata and dotenv file. The lifecycle suite also checked that the generated key was absent from the captured logs. |
| T22 Provenance | PASS | Verified source and dependency pins, local image ID and manifest digest. The Docker archive passed SHA-256 verification and reloaded with the same image configuration ID. Syft generated an SPDX inventory. |

Initial builds exposed a Bun workspace filter that skipped the gateway, a missing Qdrant shared library, a CES module entrypoint that did not launch the process, and nginx temporary paths requiring root. Those failures were corrected before the recorded candidate build.
