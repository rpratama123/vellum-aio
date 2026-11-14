# First hatch

From the Unraid Docker Console, run `vellum-aio setup`. Enter a display name, choose a provider, optionally enter the provider's model ID, and enter its API key at the hidden prompt. The setup registers the host guardian and verifies that Vellum can read the saved credential. Check `vellum-aio status` for `READY`.

The setup menu offers the fixed-model providers from the upstream CLI hatch and a custom OpenAI-compatible connection. For a custom endpoint, enter the base URL as seen from the container, including `/v1` when required, enter a model ID, and supply its key or press Enter for a keyless server. Setup makes that profile active. The container's own loopback address is only valid when the provider runs in the same network namespace.

You can interrupt at the prompts and run setup again. Once initialization starts writing state, interruptions may require repair. See [troubleshooting](TROUBLESHOOTING.md).
