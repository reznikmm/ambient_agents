<!--
SPDX-FileCopyrightText: 2026 Max Reznik <reznikmm@gmail.com>
SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
-->

# Step 1 — Give the chat a model and tools

Read [AGENTS.md](../AGENTS.md), then implement the chat loop in
`Ambient_Agents.Sessions`. Keep the existing `Sessions.Send`,
`Sessions.Reset`, and `Chat_Part` interfaces. Add configuration at the CLI
boundary as needed. The CLI records the visible conversation in
`Threads.Thread`. The session owns the messages sent to the model.

## Connect the model

Add the Ada client from GitHub with Alire.

```sh
alr with chat_completions_api --use=https://github.com/reznikmm/chat_completions_api.git
```

Call `Chat_Completions_API.Chats.Chat` using the library's message and tool
types. Configure a `Chat_Completions_API.Server` with `Set_URL`,
`Set_Request_Handler`, and `Set_API_Key` when a key is supplied. Read these
settings from the environment when starting the CLI.

| Variable | Value |
| --- | --- |
| `CHAT_COMPLETIONS_URL` | Full Chat Completions endpoint URL, such as `http://localhost:8080/v1/chat/completions` |
| `CHAT_COMPLETIONS_MODEL` | Model identifier accepted by the configured server |
| `CHAT_COMPLETIONS_API_KEY` | API key when the configured server requires one |

Use `HTTP_Requests.HTTP_Request.Post` as the transport boundary. The demo's
transport is a starting point for local `llama.cpp`. Use a TLS-capable
transport for an HTTPS endpoint. If the model or endpoint is missing, emit
an actionable chat error identifying the setting.

The client returns a complete response per request. Emit its text as one
`Text` part when present. [Client README](https://github.com/reznikmm/chat_completions_api) ·
[Tool-calling demo](https://github.com/reznikmm/chat_completions_api/blob/main/demos/src/demos.adb) ·
[Transport interface](https://github.com/reznikmm/chat_completions_api/blob/main/source/chat_completions_api-http_requests.ads)

## Implement one turn

1. Read the system instructions at the start of the turn. Prepare the request
   with those instructions, the completed conversation, and the new user
   message. The CLI uses one in-memory session.
2. Send the request with a local read-only tool named `list_open_issues` that
   returns sample issues. If the model requests tools, keep its assistant
   message with the original `tool_calls`. Emit `Tool_Call` with the name and
   arguments of each call, then execute it and append a `tool` message with the
   matching `tool_call_id` and full result. Limit the preview in `Tool_Result`
   to 400 characters. For a failed tool call, emit `Error` and send the failure
   to the model as the tool result.
3. Repeat until the model gives its final answer. Count the first request
   toward the limit of ten model requests per turn. Treat provider failure,
   an empty choices list, or needing an eleventh request as a chat error.
4. Commit the conversation when the turn completes successfully, including
   assistant messages, tool calls, and tool results. On a failed turn, keep
   the preceding complete turns intact. Emit `Done` exactly once, as the last
   part of each handled turn. `Sessions.Reset` clears the model history.

Keep the change focused on sessions, the model transport, the demo tool, CLI
configuration, and tests. The signal path remains at step 0.

## Verify step 1

Add deterministic tests in `testsuite/` with a fake `HTTP_Request` handler
that records requests and returns scripted responses. Cover a text response,
a tool round trip with its call ID and full result, the 400-character preview,
a follow-up turn, reset, provider and tool errors, and the ten-request limit.
Check that `Done` is always last.

```sh
alr build
alr -C testsuite/ run
```

With a compatible model configured, run `alr run`, ask “What open issues do
we have, and which one would you pick first?”, then ask a follow-up about the
chosen issue by context alone. The first answer should use the local tool
output. The follow-up should use the same conversation.
