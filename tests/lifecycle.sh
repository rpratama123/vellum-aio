#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CONTAINER_ENGINE=${CONTAINER_ENGINE:-docker}
engine=$CONTAINER_ENGINE
image=${1:-vellum-aio:0.12.7}
mkdir -p "$PWD/.build"
work=$(mktemp -d "$PWD/.build/lifecycle.XXXXXXXX")
name=vellum-aio-test-${work##*.}
log="$work/test.log"
volume="$work/data"
mkdir "$volume"
export VELLUM_AIO_TEST_KEY="fixture-$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"
exec > >(tee "$log") 2>&1

cleanup() {
    "$engine" logs "$name" >"$work/container.log" 2>&1 || true
    "$engine" rm -f "$name" >/dev/null 2>&1 || true
    echo "Test evidence in $work"
}
trap cleanup EXIT

launch() {
    "$engine" run -d --name "$name" --stop-timeout 45 -p 127.0.0.1::7840 \
        -v "$volume:/data:Z" "$image" >/dev/null
}
status() {
    "$engine" exec "$name" vellum-aio status
}
wait_for() {
    # Docker can allocate a new host port each time the container starts.
    local binding
    binding=$("$engine" port "$name" 7840/tcp)
    origin="http://${binding%%$'\n'*}"
    for ((attempt=0; attempt<180; attempt++)); do
        if [[ $(status 2>/dev/null || true) == "$1"* ]]; then
            if [[ $1 == READY ]] && ! curl -fsS --max-time 2 "$origin/readyz" >/dev/null 2>&1; then
                sleep 1
                continue
            fi
            echo "Observed $1"
            return
        fi
        sleep 1
    done
    status
    return 1
}

if "$engine" run --rm "$image"; then
    echo 'Image started without /data' >&2
    exit 1
fi
launch
wait_for SETUP_REQUIRED
[[ $("$engine" ps --filter "name=$name" --format '{{.Names}}') == "$name" ]]
if curl -s --max-time 3 "$origin/readyz" >/dev/null; then
    echo 'Ingress opened before hatch' >&2
    exit 1
fi
python3 tests/interactive-setup.py "$name"
wait_for READY
"$engine" exec "$name" vellum-aio doctor
"$engine" exec --tty --user 1001:1001 "$name" bash -ilc 'assistant --version'
"$engine" exec --user 1001:1001 "$name" env -u VELLUM_WORKSPACE_DIR bash -e -o pipefail -c '
    test "$(command -v assistant)" = /usr/local/bin/assistant
    test "$(command -v vellum)" = /usr/local/bin/vellum
    assistant schedules list --json | jq -e "type == \"array\" or type == \"object\"" >/dev/null
    test "$(vellum --version)" = "$(assistant --version)"
'
if "$engine" exec "$name" vellum-aio setup </dev/null; then
    echo 'Duplicate setup succeeded' >&2
    exit 1
fi
curl -fsS "$origin/assistant/__config" | jq -e '.mode == "remote-gateway" and .assistantId == "local-test"' >/dev/null
curl -fsS "$origin/assistant/pair" >"$work/spa.html"
asset=$(grep -o '/assistant/assets/[^"]*\.js' "$work/spa.html" | head -1)
curl -fsS "$origin$asset" -o /dev/null
[[ $(curl -s -o /dev/null -w '%{http_code}' "$origin/v1/guardian/init") == 404 ]]
[[ $(curl -s -o /dev/null -w '%{http_code}' "$origin/v1/conversations") == 401 ]]
"$engine" inspect --format '{{.State.Health.Status}}' "$name"

# Mint through the console and exchange through the published edge.
pairing=$("$engine" exec "$name" vellum-aio pair --url https://assistant.example.com --app --json)
device=$(python3 -c 'import uuid; print(uuid.uuid4())')
token=$(jq -nc --arg code "$(jq -er .deviceCode <<<"$pairing")" --arg dev "$device" \
    '{deviceCode:$code,deviceId:$dev,platform:"cli"}' |
    curl -fsS -H 'Content-Type: application/json' --data-binary @- "$origin/v1/remote-web/pairing-token")
access=$(jq -er .accessToken <<<"$token")
guardian=$(jq -er .guardianId <<<"$token")
[[ $(jq -er .assistantId <<<"$token") == local-test ]]
check_auth() {
    curl -fsS -H "Authorization: Bearer $access" "$origin/v1/conversations" >/dev/null
}
check_auth
"$engine" cp tests/mock-provider.py "$name:/tmp/mock-provider.py"
"$engine" exec -d "$name" python3 /tmp/mock-provider.py >/dev/null
for ((attempt=0; attempt<15; attempt++)); do
    if "$engine" exec "$name" curl -fsS http://127.0.0.1:18999/v1/models >/dev/null; then break; fi
    sleep 1
done
curl -fsS -H "Authorization: Bearer $access" -H 'Content-Type: application/json' \
    --data '{"name":"initial-model"}' -X PUT "$origin/v1/inference/active-profile" |
    jq -e '.activeProfile == "initial-model"' >/dev/null
send=$(curl -fsS -H "Authorization: Bearer $access" -H 'Content-Type: application/json' \
    --data '{"content":"Local persistence test","sourceChannel":"vellum","interface":"vellum","inferenceProfile":"initial-model"}' \
    "$origin/v1/messages")
conversation=$(jq -er .conversationId <<<"$send")
check_history() {
    curl -fsS -H "Authorization: Bearer $access" "$origin/v1/messages?conversationId=$conversation" |
        jq -e '[.. | strings | select(contains("AIO fixture reply"))] | length > 0' >/dev/null
}
for ((attempt=0; attempt<45; attempt++)); do
    if check_history; then break; fi
    sleep 1
done
check_history
echo 'Paired chat received a streamed reply from the local model fixture'

# A repeated guardian bootstrap after the first successful lease must be rejected.
repeat_code=$("$engine" exec "$name" sh -c '
    secret=$(jq -r ".assistants[0].guardianBootstrapSecret" "$HOME/.vellum.lock.json")
    curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" \
        -H "x-bootstrap-secret: $secret" --data "{\"platform\":\"cli\",\"deviceId\":\"repeat-test\"}" \
        http://127.0.0.1:7830/v1/guardian/init')
[[ $repeat_code == 403 || $repeat_code == 409 ]]
echo "Repeat guardian bootstrap returned $repeat_code"

for ((restart=1; restart<=${RESTARTS:-10}; restart++)); do
    "$engine" restart --time 45 "$name" >/dev/null
    wait_for READY
    check_auth
done
"$engine" stop --time 45 "$name" >/dev/null
"$engine" start "$name" >/dev/null
wait_for READY
check_auth
"$engine" stop --time 45 "$name" >/dev/null
"$engine" logs "$name" >"$work/before-recreate.log" 2>&1
"$engine" rm "$name" >/dev/null
launch
wait_for READY
check_auth
check_history
echo 'Existing paired token authenticated and conversation survived replacement'
refreshed=$(jq -nc --arg r "$(jq -er .refreshToken <<<"$token")" --arg d "$device" '{refreshToken:$r,deviceId:$d}' |
    curl -fsS -H "Authorization: Bearer $access" -H 'Content-Type: application/json' \
        --data-binary @- "$origin/v1/guardian/refresh")
[[ $(jq -er .guardianPrincipalId <<<"$refreshed") == "$guardian" ]]
access=$(jq -er .accessToken <<<"$refreshed")
check_auth
echo 'Paired refresh token rotated for the same guardian'
"$engine" exec "$name" vellum-aio doctor

"$engine" exec "$name" sh -c 'for path in /proc/[0-9]*/comm; do
        if [ "$(cat "$path" 2>/dev/null)" = qdrant ]; then
            pid=${path%/comm}
            kill -KILL "${pid##*/}"
            exit
        fi
    done
    exit 1'
wait_for DEGRADED
wait_for READY
check_auth
echo 'Service-group recovery preserved paired access'
"$engine" stop --time 45 "$name" >/dev/null
"$engine" logs "$name" >>"$work/before-recreate.log" 2>&1
"$engine" rm "$name" >/dev/null
"$engine" run --rm -v "$volume:/data:ro,Z" --entrypoint tar "$image" \
    --numeric-owner -czf - -C /data . >"$work/backup.tar.gz"
restored="$work/restored"
mkdir "$restored"
"$engine" run --rm -i -v "$restored:/data:Z" --entrypoint tar "$image" \
    --numeric-owner -xzf - -C /data <"$work/backup.tar.gz"
volume=$restored
launch
wait_for READY
check_auth
check_history
echo 'Offline backup restored paired access and conversation'
if grep -Fq "$VELLUM_AIO_TEST_KEY" "$log" "$work/before-recreate.log"; then
    echo 'Test credential appeared in a log' >&2
    exit 1
fi
"$engine" exec "$name" sh -c '
    mv "$HOME/instance/.vellum/protected/store.key" "$HOME/instance/.vellum/protected/store.key.held"'
"$engine" restart --time 45 "$name" >/dev/null
wait_for NEEDS_REPAIR
if curl -s --max-time 3 "$origin/readyz" >/dev/null; then
    echo 'Ingress opened with a missing vault key' >&2
    exit 1
fi
echo 'Lifecycle checks passed'
