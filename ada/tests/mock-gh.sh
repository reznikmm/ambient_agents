#!/usr/bin/env bash
set -euo pipefail
[[ $1 == api ]]
case $2 in
    */issues\?*)
        phase=$(cat "$GITHUB_TEST_PHASE")
        jq -cn --argjson phase "$phase" '[range(0;$phase+1) | {id:(9100+.),number:(9100+.),title:"Offline polled issue",body:"",user:{login:"alice",type:"User"},html_url:"https://example.invalid/issue"}]'
        ;;
    */issues/comments\?*) printf '[]\n' ;;
    */actions/runs\?*) printf '{"workflow_runs":[]}\n' ;;
    *) printf 'Unexpected gh request: %s\n' "$2" >&2; exit 1 ;;
esac
