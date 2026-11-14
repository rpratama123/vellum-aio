# Vellum AIO for Unraid

Vellum Assistant 0.12.7 in one Linux/amd64 container. The image runs the assistant, gateway, credential executor, Qdrant and the upstream remote web ingress. All durable state lives on one `/data` bind mount. On Unraid, the existing Cloudflared tunnel routes through Caddy on `proxynet`.

```sh
scripts/build-local.sh vellum-aio:0.12.7
mkdir -p ./appdata
docker run -d --name vellum-aio --stop-timeout 45 \
  -v "$PWD/appdata:/data" -p 127.0.0.1:7840:7840 vellum-aio:0.12.7
docker exec -it vellum-aio vellum-aio setup
docker exec vellum-aio vellum-aio status
```

Set `CONTAINER_ENGINE=podman` for local Podman builds and tests. On SELinux hosts, label a dedicated local appdata bind mount with `:Z`. Use `tests/lifecycle.sh vellum-aio:0.12.7` for the disposable local smoke and persistence test. The test uses Python pexpect, curl and jq.

- [Unraid template](unraid/my-Vellum-AIO.xml) and [installation](docs/INSTALL-UNRAID.md)
- [First hatch](docs/FIRST-HATCH.md), [Cloudflared and Caddy](docs/CLOUDFLARED-EXISTING.md), and [pairing](docs/PAIR-IOS-WINDOWS.md)
- [Operations](docs/OPERATIONS.md), [troubleshooting](docs/TROUBLESHOOTING.md), and [limitations](docs/LIMITATIONS.md)
- [Pinned source audit](docs/SOURCE-AUDIT.md), [build provenance](docs/BUILD-PROVENANCE.md), and [test report](docs/TEST-REPORT.md)

The GHCR workflow is a manual candidate release workflow. Use unique tags and deploy by digest when available. See the test report before deploying to Unraid.
