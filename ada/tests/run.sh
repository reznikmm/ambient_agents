#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."
temporary=$(mktemp -d)
server_pid=
stream_pid=
model_pid=
cleanup() {
    status=$?
    if ((status != 0)) && [[ -f $temporary/server.log ]]; then
        tail -30 "$temporary/server.log" >&2
    fi
    if [[ -n $stream_pid ]]; then kill "$stream_pid" 2>/dev/null || true; wait "$stream_pid" 2>/dev/null || true; fi
    if [[ -n $server_pid ]]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
    if [[ -n $model_pid ]]; then kill "$model_pid" 2>/dev/null || true; wait "$model_pid" 2>/dev/null || true; fi
    rm -rf -- "$temporary"
}
trap cleanup EXIT
for program in curl jq timeout; do command -v "$program" >/dev/null; done
ada/bin/ambient_evals
for step in ${TEST_STEPS:-0 1 2 3 4 5 6 7 8}; do
    expected=0
    case $step in 4) expected=2 ;; 5) expected=3 ;; 6) expected=5 ;; 7|8) expected=6 ;; esac
    ada/bin/ambient_evals --json --step "$step" > "$temporary/evals.json"
    jq -e --argjson expected "$expected" '.passing == $expected and .total == 6' "$temporary/evals.json" >/dev/null
done
mkdir -p "$temporary/memory"
cp memory/watches.md "$temporary/memory/watches.md"
printf 'At most 3 pings a day.\n' > "$temporary/memory/preferences.md"
export STATE_PATH="$temporary/state.json" MEMORY_DIR="$temporary/memory" REGISTRY_PATH="$temporary/registry"
export GITHUB_REPO= GITHUB_WEBHOOK_SECRET=offline-secret GATE_MODE=rules WORKER_MODE=sim
export CHAT_COMPLETIONS_URL= OPENAI_API_KEY= OPENROUTER_API_KEY= AI_GATEWAY_API_KEY= SLACK_WEBHOOK_URL=
# Override TEST_PORT when another integration suite uses the default port.
export PORT=${TEST_PORT:-19421}
start_server() {
    ada/bin/ambient_workshop > "$temporary/stdout" 2> "$temporary/server.log" &
    server_pid=$!
    for ((attempt = 0; attempt < 100; attempt++)); do
        if curl -fsS "http://127.0.0.1:$PORT/api/state" > "$temporary/state-response"; then return; fi
        sleep .1
    done
    cat "$temporary/server.log" >&2
    return 1
}
stop_server() {
    kill "$server_pid"
    wait "$server_pid" 2>/dev/null || true
    server_pid=
}
post() { curl -fsS -H 'Content-Type: application/json' --data-binary "$2" "http://127.0.0.1:$PORT$1"; }
get() { curl -fsS "http://127.0.0.1:$PORT$1"; }
start_server
get / > "$temporary/app.html"
rg -q 'text/html|<!DOCTYPE|<!doctype' "$temporary/app.html"
get /stage > "$temporary/stage.html"
rg -Fq '<title>Workshop stage</title>' "$temporary/stage.html"
get '/db?instance=stage&embed=1' > "$temporary/db.html"
rg -Fq '<title>Agent storage</title>' "$temporary/db.html"
post /api/trigger '{"scenario":"ci-failed"}' | jq -e '.injected==1' >/dev/null
sleep .5
get /api/state | jq -e '.stats.workerRuns==1 and .stats.sessions==1 and (.wakeups|length)==1' >/dev/null
post /api/clock '{"advanceMinutes":11}' | jq -e '.clock>0' >/dev/null
get /api/state | jq -e '.stats.timersFired==1 and .stats.workerRuns==2' >/dev/null
post /api/watches '{"add":"PRs about cats"}' | jq -e '.watches|index("PRs about cats")!=null' >/dev/null
post /api/trigger '{"scenario":"cat-pr"}' >/dev/null
sleep .5
get /api/state > "$temporary/ask"
ask_id=$(jq -r '.asks[0].id' "$temporary/ask")
[[ $ask_id != null ]]
post /api/answer "{\"id\":$ask_id,\"yes\":false}" | jq -e '.ok==true' >/dev/null
get /api/thread | jq -e '[.entries[].text]|any(contains("Left it as it is"))' >/dev/null
post /api/chat '{"message":"hello"}' > "$temporary/chat"
jq -se '.[0].t=="text" and .[-1].t=="done"' "$temporary/chat" >/dev/null
code=$(curl -sS -o "$temporary/error" -w '%{http_code}' "http://127.0.0.1:$PORT/api/memory/file?path=..%2FREADME.md")
[[ $code == 400 ]]
# A published HMAC-SHA256 test vector, then an actual signed delivery.
# openssl is used only by the test sender; verification is native Ada.
payload='{"action":"opened","repository":{"full_name":"demo/app"},"issue":{"id":2001,"number":201,"title":"Test issue","body":"","user":{"login":"alice","type":"User"}}}'
signature=$(printf '%s' "$payload" | openssl dgst -sha256 -hmac offline-secret | awk '{print $NF}')
code=$(curl -sS -o "$temporary/webhook" -w '%{http_code}' -H 'Content-Type: application/json' -H 'X-GitHub-Event: issues' -H "X-Hub-Signature-256: sha256=$signature" --data-binary "$payload" "http://127.0.0.1:$PORT/webhooks/github")
[[ $code == 202 ]]
code=$(curl -sS -o "$temporary/webhook" -w '%{http_code}' -H 'Content-Type: application/json' -H 'X-GitHub-Event: issues' -H 'X-Hub-Signature-256: sha256=bad' --data-binary "$payload" "http://127.0.0.1:$PORT/webhooks/github")
[[ $code == 401 ]]
# Long-lived SSE survives subsequent requests and forwards updates.
curl -NsS "http://127.0.0.1:$PORT/api/stream" > "$temporary/stream" &
stream_pid=$!
sleep .2
post /api/trigger '{"scenario":"new-issue","title":"Streaming issue"}' >/dev/null
sleep .5
rg -q '"t":"snapshot"' "$temporary/stream"
rg -q 'Streaming issue' "$temporary/stream"
kill "$stream_pid"
wait "$stream_pid" 2>/dev/null || true
stream_pid=
# State survives a process restart: wakeups, sessions, notifications and thread.
get /api/thread > "$temporary/thread-before"
stop_server
start_server
get /api/thread > "$temporary/thread-after"
cmp "$temporary/thread-before" "$temporary/thread-after"
post /api/digest '{}' | jq -e '.items>0' >/dev/null
post /api/digest '{}' | jq -e '.items==0' >/dev/null
post /api/trigger '{"scenario":"new-issue","title":"For the morning digest"}' >/dev/null
sleep .5
get /api/state > "$temporary/before-jump"
post /api/clock '{"jumpTo":"09:00"}' > "$temporary/after-jump"
jq -e --slurpfile before "$temporary/before-jump" '.clock > $before[0].clock' "$temporary/after-jump" >/dev/null
get /api/thread | jq -e '[.entries[]|select(.kind=="digest")]|length==2' >/dev/null
post /api/digest '{}' | jq -e '.items==0' >/dev/null
stop_server
# MCP speaks the pinned draft, using exactly the same tools as chat.
jq -cn '
 def request($id;$method;$extra): {jsonrpc:"2.0",id:$id,method:$method,params:({_meta:{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}+$extra)};
 request(1;"server/discover";{}),
 request(2;"tools/list";{}),
 request(3;"tools/call";{name:"memory_write",arguments:{path:"preferences.md",content:"At most 1 ping a day. Привіт"}}),
 request(4;"tools/call";{name:"memory_read",arguments:{path:"preferences.md"}}),
 request(5;"tools/call";{name:"read_file",arguments:{path:"../mcp/README.md"}}),
 request(6;"tools/call";{name:"remind",arguments:{what:"review PR",inMinutes:30}}),
 request(7;"unknown";{})' > "$temporary/mcp-requests"
ada/bin/ambient_workshop --mcp < "$temporary/mcp-requests" > "$temporary/mcp-replies" 2> "$temporary/mcp-log"
jq -se 'length==7 and .[0].result.supportedVersions==["2026-07-28"] and (.[1].result.tools|length)>=15 and .[3].result.content[0].text=="At most 1 ping a day. Привіт" and .[4].result.isError==true and .[6].error.code == -32601' "$temporary/mcp-replies" >/dev/null
# ACP: typed v2 handshake, prompt acceptance followed by updates, permissions,
# and the same signal reusing a session for a second subject.
export WORKER_MODE=acp ACP_AGENT="$PWD/ada/tests/mock-acp.sh" ACP_TEST_LOG="$temporary/acp-requests"
start_server
# The simulator reuses its subject numbers after a process restart. Move past
# the persisted quiet window before delivering new work on those subjects.
post /api/clock '{"advanceMinutes":6}' >/dev/null
post /api/trigger '{"scenario":"new-issue","title":"ACP issue 1"}' >/dev/null
sleep 1
post /api/trigger '{"scenario":"new-issue","title":"ACP issue 2"}' >/dev/null
sleep 1
get /api/thread > "$temporary/acp-thread"
jq -e '[.entries[].text]|any(contains("Привіт from ACP"))' "$temporary/acp-thread" >/dev/null
jq -se '[.[]|select(.method=="session/new")]|length==1' "$temporary/acp-requests" >/dev/null
jq -se '[.[]|select(.method=="session/prompt")]|length==2' "$temporary/acp-requests" >/dev/null
jq -se '[.[]|select(.id==900 and .result.outcome.outcome=="cancelled")]|length==2' "$temporary/acp-requests" >/dev/null
stop_server
start_server
post /api/clock '{"advanceMinutes":12}' >/dev/null
post /api/trigger '{"scenario":"new-issue","title":"ACP after restart"}' >/dev/null
sleep 1
get /api/thread | jq -e '[.entries[].text]|any(contains("Привіт from ACP"))' >/dev/null
jq -se '[.[]|select(.method=="session/resume")]|length==1' "$temporary/acp-requests" >/dev/null
jq -se '[.[]|select(.method=="session/new")]|length==1' "$temporary/acp-requests" >/dev/null
stop_server
# Verify the real Chat_Completions_API serializer, HTTP handler and tool loop.
export WORKER_MODE=sim MODEL_TEST_PORT=${MODEL_TEST_PORT:-19422} MODEL_TEST_LOG="$temporary/model-requests"
export CHAT_COMPLETIONS_URL="http://127.0.0.1:$MODEL_TEST_PORT/v1/chat/completions" CHAT_MODEL=offline-model
export OPENAI_API_KEY= OPENROUTER_API_KEY=offline-test-token
ada/bin/ambient_model_fixture > "$temporary/model-output" 2> "$temporary/model-log" &
model_pid=$!
sleep .2
start_server
post /api/chat '{"message":"Read my preferences"}' > "$temporary/model-chat"
jq -se 'map(.t)==["tool","tool-result","text","done"] and .[0].name=="memory_read" and (.[2].text|contains("Привіт"))' "$temporary/model-chat" >/dev/null
rg -q '"role":"tool"' "$temporary/model-requests"
rg -q 'Authorization: Bearer offline-test-token' "$temporary/model-requests"
wait "$model_pid"
model_pid=
stop_server
# GitHub polling establishes a baseline, then ingests new items once, including
# when the seen-ID store is reopened after a process restart.
mkdir -p "$temporary/bin"
ln -s "$PWD/ada/tests/mock-gh.sh" "$temporary/bin/gh"
export PATH="$temporary/bin:$PATH" GITHUB_TEST_PHASE="$temporary/github-phase"
export GITHUB_REPO=demo/app GITHUB_SOURCE=poll GITHUB_POLL_MS=100
printf '0\n' > "$GITHUB_TEST_PHASE"
start_server
sleep .4
get /api/state | jq -e '.stats.workerRuns==0' >/dev/null
printf '1\n' > "$GITHUB_TEST_PHASE"
for ((attempt = 0; attempt < 50; attempt++)); do
    if get /api/state | jq -e '.stats.workerRuns==1' >/dev/null; then break; fi
    sleep .1
done
get /api/state | jq -e '.stats.workerRuns==1' >/dev/null
stop_server
start_server
sleep .4
get /api/state | jq -e '.stats.workerRuns==0' >/dev/null
printf '2\n' > "$GITHUB_TEST_PHASE"
for ((attempt = 0; attempt < 50; attempt++)); do
    if get /api/state | jq -e '.stats.workerRuns==1' >/dev/null; then break; fi
    sleep .1
done
get /api/state | jq -e '.stats.workerRuns==1' >/dev/null
stop_server
printf 'Ada integration tests: PASS (steps, HTTP, signatures, asks, memory, persistence, SSE, MCP, ACP, Chat Completions, GitHub polling)\n'
