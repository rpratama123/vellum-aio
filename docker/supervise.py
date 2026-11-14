"""PID 1 owns the local Vellum service group and reaps orphaned children."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import socket
import sqlite3
import subprocess
import sys
import time
from urllib.request import build_opener, ProxyHandler

HOME = Path("/data/home")
RUN = Path("/run/vellum")
APP = Path("/opt/vellum")
INSTANCE = HOME / "instance"
WORKSPACE = INSTANCE / ".vellum/workspace"
PROTECTED = INSTANCE / ".vellum/protected"
LOCKFILE = HOME / ".vellum.lock.json"
SEAL = HOME / ".aio-identity.json"
PENDING = HOME / ".aio-hatch"
http = build_opener(ProxyHandler({}))
stopping = False


def read_json(path):
    return json.loads(path.read_text())


def require(condition, message):
    if not condition:
        raise ValueError(message)


def entry():
    lock = read_json(LOCKFILE)
    entries = lock["assistants"]
    require(len(entries) == 1, "expected one upstream assistant entry")
    agent = entries[0]
    assistant_id = agent["assistantId"]
    require(re.fullmatch(r"[a-z0-9][a-z0-9-]{0,62}", assistant_id), "invalid assistant ID")
    require(lock["activeAssistant"] == assistant_id, "invalid active assistant")
    require(agent["resources"]["instanceDir"] == str(INSTANCE), "invalid instance path")
    for key in (agent["resources"]["signingKey"], agent["guardianBootstrapSecret"]):
        require(re.fullmatch(r"[0-9a-f]{64}", key), "missing or malformed signing/bootstrap key")
    return agent


def identity(agent, deep=False):
    seal = read_json(SEAL)
    assistant_id = agent["assistantId"]
    token = read_json(HOME / ".config/vellum/assistants" / assistant_id / "guardian-token.json")
    require(seal["id"] == assistant_id and seal["guardian"] == token["guardianPrincipalId"]
            and token["refreshToken"] and token["accessToken"], "guardian identity mismatch")
    signing = agent["resources"]["signingKey"]
    require(hashlib.sha256(signing.encode()).hexdigest() == seal["signing"], "signing key changed")
    daemon_key = WORKSPACE / "deprecated/actor-token-signing-key"
    require(daemon_key.read_bytes().hex() == signing, "assistant signing key is missing or changed")
    vault_path = PROTECTED / "store.key"
    credentials = PROTECTED / "keys.enc"
    if seal["vault"] is not None or credentials.exists() or vault_path.exists():
        vault = vault_path.read_bytes()
        require(len(vault) == 32, "invalid vault key")
        require(seal["vault"] is None or hashlib.sha256(vault).hexdigest() == seal["vault"], "vault key changed")
        require(credentials.stat().st_size > 0, "empty credential store")
    require((PROTECTED / "guardian-init.lock").stat().st_size > 0
            and 0 in read_json(PROTECTED / "guardian-init-consumed.json"), "guardian bootstrap guard is incomplete")
    if "bootstrap" in seal:
        bootstrap = agent["guardianBootstrapSecret"].encode()
        require(hashlib.sha256(bootstrap).hexdigest() == seal["bootstrap"], "guardian bootstrap key changed")
    for path in (WORKSPACE / "data/db/assistant.db", PROTECTED / "gateway.sqlite"):
        with path.open("rb") as file:
            require(file.read(16) == b"SQLite format 3\0", f"invalid SQLite header in {path.name}")
        if deep:
            with sqlite3.connect(path.as_uri() + "?mode=ro", uri=True, timeout=5) as database:
                require(database.execute("PRAGMA quick_check(1)").fetchone() == ("ok",),
                        f"SQLite integrity check failed in {path.name}")


def setup_active():
    with (RUN / "setup.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return False
        except BlockingIOError:
            return True


def report(state, detail=""):
    path = RUN / "state"
    message = state + (" " + detail if detail else "")
    if not path.exists() or path.read_text().strip() != message:
        print(message, flush=True)
        staging = RUN / "state.tmp"
        staging.write_text(message + "\n")
        staging.replace(path)


def healthy(port, route, vellum=False):
    try:
        with http.open(f"http://127.0.0.1:{port}{route}", timeout=1) as response:
            return response.status == 200 and (not vellum or json.load(response).get("ready") is True)
    except (OSError, ValueError):
        return False


def ces_ready():
    try:
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(1)
            connection.connect(str(RUN / "ipc/ces.sock"))
            return True
    except OSError:
        return False


def backend_ready():
    return (ces_ready() and healthy(6333, "/readyz") and healthy(7821, "/readyz", vellum=True)
            and healthy(7830, "/readyz", vellum=True))


def spawn(service, command, env=None, cwd=APP):
    print(f"Starting {service}", flush=True)
    child = subprocess.Popen(command, cwd=cwd, env=env, start_new_session=True)
    child.service = service
    children.append(child)


def stop_services():
    for sig, grace in ((signal.SIGTERM, 35), (signal.SIGKILL, 2)):
        for child in reversed(children):
            try:
                os.killpg(child.pid, sig)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + grace
        while time.monotonic() < deadline and any(c.poll() is None for c in children):
            time.sleep(0.1)
    children.clear()


def reap_children():
    for child in children:
        if child.poll() is not None:
            raise RuntimeError(f"{child.service} exited ({child.returncode})")
    # Only reap via waitpid for adopted descendants after consulting Popen.
    while True:
        try:
            pid, status = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            break
        if pid == 0:
            break
        for child in children:
            if child.pid == pid:
                child.returncode = os.waitstatus_to_exitcode(status)
                raise RuntimeError(f"{child.service} exited ({child.returncode})")


def launch(agent, initial):
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    PROTECTED.mkdir(parents=True, exist_ok=True)
    for item in (RUN / "ipc").glob("*.sock"):
        if item.is_socket():
            item.unlink()
    shared = dict(os.environ, VELLUM_WORKSPACE_DIR=str(WORKSPACE),
                  GATEWAY_SECURITY_DIR=str(PROTECTED), CREDENTIAL_SECURITY_DIR=str(PROTECTED),
                  VELLUM_ASSISTANT_NAME=agent["assistantId"])
    signed = dict(shared, ACTOR_TOKEN_SIGNING_KEY=agent["resources"]["signingKey"])
    assistant = signed.copy()
    if initial:
        overlay = WORKSPACE / ".aio-initial-config.json"
        overlay.write_text(PENDING.read_text())
        assistant["VELLUM_DEFAULT_WORKSPACE_CONFIG_PATH"] = str(overlay)

    spawn("Qdrant", ["qdrant", "--config-path", str(APP / "aio/qdrant.yaml")], cwd=HOME)
    spawn("CES", ["bun", "src/main.ts"], shared, APP / "credential-executor")
    spawn("assistant", ["bun", "src/daemon/main.ts"], assistant, APP / "assistant")
    gateway = dict(signed, GUARDIAN_BOOTSTRAP_SECRET=agent["guardianBootstrapSecret"])
    spawn("gateway", ["bun", "src/index.ts"], gateway, APP / "gateway")


def launch_ingress():
    subprocess.run(["bun", str(APP / "aio/ingress.ts")], check=True, timeout=20)
    spawn("ingress", ["nginx", "-p", str(RUN) + "/", "-c", "nginx.conf", "-g", "daemon off;"])


def wait_for_ready(agent, initial):
    report("HATCHING" if initial else "STARTING")
    launch(agent, initial)
    deadline = time.monotonic() + 125
    while not stopping and time.monotonic() < deadline:
        reap_children()
        if initial and not setup_active() and not SEAL.exists():
            return False
        if backend_ready():
            if initial and not SEAL.exists():
                report("HATCHING_READY")
            else:
                identity(agent, deep=True)
                launch_ingress()
                return True
        time.sleep(0.5)
    if not stopping:
        raise RuntimeError("service startup timed out")
    return False


def supervise():
    failures = 0
    while not stopping:
        initial = not SEAL.exists()
        active = setup_active()
        try:
            if initial:
                if not any(path.name != ".cache" for path in HOME.iterdir()):
                    require(os.access(HOME, os.W_OK | os.X_OK), "appdata is not writable by UID 1001")
                    report("SETUP_REQUIRED")
                    time.sleep(0.5)
                    continue
                if not (active and PENDING.exists() and LOCKFILE.exists()):
                    report("HATCHING" if active else "NEEDS_REPAIR", "" if active else "incomplete setup")
                    time.sleep(0.5)
                    continue
            agent = entry()
            if not initial:
                identity(agent, deep=True)
        except (OSError, ValueError, KeyError, TypeError, sqlite3.Error) as error:
            if not (initial and active):
                report("NEEDS_REPAIR", str(error))
            time.sleep(0.5)
            continue

        started = time.monotonic()
        try:
            if not wait_for_ready(agent, initial):
                continue
            unhealthy = 0
            while not stopping:
                reap_children()
                if backend_ready() and healthy(7840, "/readyz", vellum=True):
                    unhealthy = 0
                    report("READY")
                else:
                    unhealthy += 1
                    if unhealthy > 1:
                        report("DEGRADED", "service readiness check failed")
                    if unhealthy >= 10:
                        raise RuntimeError("services did not recover")
                time.sleep(2)
                if time.monotonic() - started > 180:
                    failures = 0
        except (RuntimeError, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
            failures += 1
            report("DEGRADED", str(error))
            if failures >= 5:
                report("NEEDS_REPAIR", "service retry limit reached; review logs and restart")
                while not stopping:
                    time.sleep(1)
            else:
                deadline = time.monotonic() + min(2 ** failures, 30)
                while not stopping and time.monotonic() < deadline:
                    time.sleep(0.5)
        finally:
            stop_services()


def request_stop(*_args):
    global stopping
    stopping = True


if __name__ == "__main__":
    if sys.argv[1:] == ["doctor"]:
        print((RUN / "state").read_text().strip())
        if SEAL.exists():
            identity(entry(), deep=True)
            print("Persistent identity, vault key and SQLite files verified.")
        sys.exit(0)
    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    children = []
    with (Path("/data") / ".vellum-runtime.lock").open("a") as volume_lock:
        fcntl.flock(volume_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        supervise()
