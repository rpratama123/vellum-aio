# Build provenance

The Dockerfile fetches the complete immutable upstream commit listed in `versions.env` and checks the unchanged upstream lockfile by SHA-256. Bun, Debian and Qdrant images are referenced by registry digests. A signed 2026-11-14 Debian snapshot pins system package resolution. The build uses the upstream plugin catalog generators and builds the web application from the same Vellum revision.

`scripts/build-local.sh` builds Linux/amd64 and prints the image ID. `scripts/image-evidence.sh IMAGE OUTPUT` records the image ID, upstream pins, Debian packages, frozen Bun dependency resolution and an SPDX SBOM. The publish workflow tests and transfers the exact image before pushing, then records the GHCR repository digest. Registry publication requires a manually dispatched workflow from the owner.

On GitHub, open **Actions → Publish Vellum AIO candidate → Run workflow**, select the default branch, and enter a new candidate tag such as `0.12.7-aio.1`. The workflow publishes to `ghcr.io/rpratama123/vellum-aio` using the workflow's `GITHUB_TOKEN`. Use the digest from the run summary for Unraid. GHCR packages start private, so set the package visibility to Public if you want anonymous pulls. [GitHub Container registry documentation](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
