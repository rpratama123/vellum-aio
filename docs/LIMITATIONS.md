# Scope

The candidate targets Linux/amd64 and one assistant in a native Unraid container. Vellum services share UID 1001 and filesystem access in the container. It uses the upstream local trust and credential paths with only the public edge listening off loopback.

Features requiring a host Docker socket, sibling containers, a privileged desktop environment, or cloud-managed identity are outside this deployment. Local-browser automation and Meet were not part of image verification. Native client tests must use real supported client builds. The upstream release lists macOS desktop assets, so use a separately installed compatible Windows CLI or browser when validating Windows.
