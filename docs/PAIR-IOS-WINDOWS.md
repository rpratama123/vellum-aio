# Pair iOS and Windows

After the Caddy hostname serves the Vellum SPA and the container reports `READY`, generate a new code for each device from the Docker Console.

- iOS native app. Run `vellum-aio pair --url https://assistant.example.com --app` and scan the QR with a compatible Vellum app installed.
- Windows browser. Run `vellum-aio pair --url https://assistant.example.com` and open the HTTPS pairing link on Windows.
- Windows CLI. Run the printed `vellum connect import "<pairing-link>"` in a compatible Vellum CLI on Windows. Start a session with `vellum client`.
- Device-initiated. Open the HTTPS origin on the device and approve the displayed code from the Docker Console with `vellum-aio pair --web-approve <code>`.

When the template's Public HTTPS origin is set, `--url` can be omitted. Pairing codes expire and are single-use. Keep the HTTPS hostname stable after pairing. See the test report for the scope of native client verification. [Upstream pairing guide](https://www.vellum.ai/docs/hosting-options/pair-a-device)
