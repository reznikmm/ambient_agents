#!/usr/bin/env bash
# Four independent Ada processes, with separate state and memory directories.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$root"
if [[ -f .env.ada ]]; then
    set -a
    source .env.ada
    set +a
fi
state_root="$root/.data/ada"
export REGISTRY_PATH="$state_root/registry"
stop_instance() {
    local name=$1 pid executable
    [[ -f $state_root/$name/pid ]] || return 0
    read -r pid < "$state_root/$name/pid"
    if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
        executable=$(readlink "/proc/$pid/exe" || true)
        if [[ $executable == "$root/ada/bin/ambient_workshop"* ]]; then
            kill -TERM "$pid"
            for ((attempt = 0; attempt < 60; attempt++)); do
                kill -0 "$pid" 2>/dev/null || break
                sleep .1
            done
            if kill -0 "$pid" 2>/dev/null; then
                # Processes started below have their own process group.
                kill -KILL -- "-$pid" 2>/dev/null || true
            fi
        fi
    fi
    rm -f -- "$state_root/$name/pid"
}
start_instance() {
    local name=$1 port=$2 step=$3 mode=${4:---serve}
    stop_instance "$name"
    mkdir -p "$state_root/$name/memory"
    for file in watches.md preferences.md; do
        if [[ ! -f $state_root/$name/memory/$file ]]; then
            cp -- "memory/$file" "$state_root/$name/memory/$file"
        fi
    done
    INSTANCE="$name" PORT="$port" DASHBOARD_PORT="$port" WORKSHOP_STEP="$step" \
        STATE_PATH="$state_root/$name/agent.json" MEMORY_DIR="$state_root/$name/memory" \
        setsid ada/bin/ambient_workshop "$mode" > "$state_root/$name/server.log" 2>&1 < /dev/null &
    local pid=$!
    printf '%s\n' "$pid" > "$state_root/$name/pid"
    for ((attempt = 0; attempt < 100; attempt++)); do
        if curl -fsS "http://127.0.0.1:$port/api/state" >/dev/null 2>&1; then
            printf '%s: http://127.0.0.1:%s\n' "$name" "$port"
            return
        fi
        if ! kill -0 "$pid" 2>/dev/null; then break; fi
        sleep .1
    done
    cat "$state_root/$name/server.log" >&2
    stop_instance "$name"
    return 1
}
case ${1:-start} in
    start)
        alr -C ada build
        trap 'for name in dashboard stage finished naive; do stop_instance "$name"; done' ERR
        start_instance naive 4101 3
        start_instance finished 4102 8
        start_instance stage 4103 1
        start_instance dashboard "${DASHBOARD_PORT:-4000}" 8 --dashboard
        ;;
    stop)
        for name in dashboard stage finished naive; do stop_instance "$name"; done
        ;;
    *) printf 'usage: %s [start|stop]\n' "$0" >&2; exit 2 ;;
esac
