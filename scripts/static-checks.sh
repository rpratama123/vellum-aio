#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scripts/verify-pins.sh
for file in docker/entrypoint docker/vellum-aio scripts/*.sh tests/*.sh; do
    bash -n "$file"
done
python3 - <<'PY'
from pathlib import Path
from xml.etree import ElementTree as ET

template = ET.parse("unraid/my-Vellum-AIO.xml").getroot()
assert template.tag == "Container" and template.attrib["version"] == "2"
assert template.findtext("Name") == "vellum-aio"
assert template.findtext("Privileged") == "false"
assert template.findtext("Network") == "proxynet"
assert template.findtext("ExtraParams") == "--stop-timeout=45"
paths = [config for config in template.findall("Config") if config.get("Type") == "Path"]
assert len(paths) == 1 and paths[0].get("Target") == "/data"
for path in [*Path("docker").glob("*.py"), *Path("tests").glob("*.py")]:
    compile(path.read_bytes(), str(path), "exec")
PY
