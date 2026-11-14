# Install on Unraid

1. Load your built image into Unraid or use a published GHCR image and record its digest. Update the Repository field in `unraid/my-Vellum-AIO.xml` if you use a local image or pin a published digest.
2. Import the XML as a native Docker user template. In Docker → Add Container select the template, ensure Image and Network are correct, and bind persistent appdata to `/data`. Attach it to `proxynet` for Caddy. Keep the container name `vellum-aio` for Docker DNS.
3. Start the container. Look for `SETUP_REQUIRED` in Docker logs. Open Console and complete [first hatch](FIRST-HATCH.md).
4. After `READY`, set up [the existing tunnel and Caddy hostname](CLOUDFLARED-EXISTING.md), then [pair your clients](PAIR-IOS-WINDOWS.md).
5. Enable autostart and verify that your paired clients reconnect after a restart.

Allow 45 seconds for graceful shutdown. Keep the application data directory on persistent storage backed by an SSD pool where practical. The runtime creates a private service directory owned by UID/GID 1001 inside that directory. [Native Unraid Docker management](https://docs.unraid.net/unraid-os/using-unraid-to/run-docker-containers/overview/)

To load the local candidate, copy the image archive to Unraid and run `docker load -i /path/to/vellum-aio-0.12.7-amd64.tar.gz` from an Unraid terminal. Check the tag printed by the load command and use that tag in the template's Repository field. The archive does not contain your appdata.
