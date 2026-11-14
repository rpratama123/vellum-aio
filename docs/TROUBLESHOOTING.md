# Troubleshooting

| Symptom | What to check |
| --- | --- |
| `SETUP_REQUIRED` after a previous hatch | Check the host side of the bind mount and confirm it contains the existing `home/.vellum.lock.json`. |
| `NEEDS_REPAIR` | Stop the service and make a consistent snapshot. Check logs and `vellum-aio doctor`. Restore a matching complete backup if identity, keys or database files are missing. For a fresh interrupted setup with no identity to preserve, keep the incomplete directory offline and use a new empty appdata directory. |
| Guardian bootstrap refuses another lease | The bootstrap is single-use. Existing sessions use the persistent signing key and refresh state. Check the guard and databases in the backup. |
| 502 from Caddy or Cloudflare | Check `vellum-aio status` and verify the tunnel's matching Caddy listener and Docker DNS for `vellum-aio:7840`. |
| Pairing SPA or assets missing | Test `/assistant/` and `/assistant/__config` over the same origin. Route to 7840, the bundled ingress. |
| 401 or 403 | Check the pairing code expiry, whether the advertised origin is stable and whether Cloudflare added an auth or challenge page. |
| Read-only connection or missing source channel | Reconnect using the self-hosted pairing link and record the client version and the failing send route for diagnosis. |
