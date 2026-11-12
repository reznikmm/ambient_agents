#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$root"
if [[ -f .env.ada ]]; then
    set -a
    source .env.ada
    set +a
fi
if [[ ! -x ada/bin/ambient_workshop ]]; then
    alr -C ada build >&2
fi
exec ada/bin/ambient_workshop "$@"
