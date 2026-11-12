#!/usr/bin/env bash
set -euo pipefail
sessions=0
while IFS= read -r message; do
    printf '%s\n' "$message" >> "$ACP_TEST_LOG"
    method=$(jq -r '.method // "reply"' <<< "$message")
    identifier=$(jq -c '.id' <<< "$message")
    case "$method" in
        initialize)
            jq -cn --argjson id "$identifier" '{jsonrpc:"2.0",id:$id,result:{protocolVersion:2,info:{name:"offline-adapter",version:"1"},capabilities:{session:{}}}}'
            ;;
        session/new)
            sessions=$((sessions + 1))
            jq -cn --argjson id "$identifier" --arg session "s$sessions" '{jsonrpc:"2.0",id:$id,result:{sessionId:$session}}'
            ;;
        session/resume)
            jq -cn --argjson id "$identifier" '{jsonrpc:"2.0",id:$id,result:{}}'
            ;;
        session/prompt)
            session=$(jq -r '.params.sessionId' <<< "$message")
            jq -cn --arg session "$session" '{jsonrpc:"2.0",method:"session/update",params:{sessionId:$session,update:{sessionUpdate:"state_update",state:"running"}}}'
            jq -cn --arg session "$session" '{jsonrpc:"2.0",id:900,method:"session/request_permission",params:{sessionId:$session,title:"Edit file",options:[{optionId:"yes",name:"Allow",kind:"allow_once"}]}}'
            # Prompt response is acceptance; text arrives after the response.
            jq -cn --argjson id "$identifier" '{jsonrpc:"2.0",id:$id,result:{messageId:"u1"}}'
            result='{"summary":"Привіт from ACP","action":"draft review","reversible":true,"confidence":0.8}'
            jq -cn --arg session "$session" '{jsonrpc:"2.0",method:"session/update",params:{sessionId:$session,update:{sessionUpdate:"agent_message_chunk",messageId:"m1",content:{type:"text",text:"discarded draft"}}}}'
            jq -cn --arg session "$session" '{jsonrpc:"2.0",method:"session/update",params:{sessionId:$session,update:{sessionUpdate:"agent_message",messageId:"m1",content:null}}}'
            jq -cn --arg session "$session" --arg text "$result" '{jsonrpc:"2.0",method:"session/update",params:{sessionId:$session,update:{sessionUpdate:"agent_message_chunk",messageId:"m1",content:{type:"text",text:$text}}}}'
            # Omission must preserve text already assembled from chunks.
            jq -cn --arg session "$session" '{jsonrpc:"2.0",method:"session/update",params:{sessionId:$session,update:{sessionUpdate:"agent_message",messageId:"m1"}}}'
            # Full content replaces the assembled text, rather than appending.
            jq -cn --arg session "$session" --arg text "$result" '{jsonrpc:"2.0",method:"session/update",params:{sessionId:$session,update:{sessionUpdate:"agent_message",messageId:"m1",content:[{type:"text",text:$text}]}}}'
            jq -cn --arg session "$session" '{jsonrpc:"2.0",method:"session/update",params:{sessionId:$session,update:{sessionUpdate:"state_update",state:"idle",stopReason:"end_turn"}}}'
            ;;
    esac
done
