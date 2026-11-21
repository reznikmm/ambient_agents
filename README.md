# Ambient Agents in Ada

[![Build with Alire](https://github.com/reznikmm/ambient_agents/actions/workflows/alire.yml/badge.svg)](https://github.com/reznikmm/ambient_agents/actions/workflows/alire.yml)
[![REUSE status](https://api.reuse.software/badge/github.com/reznikmm/ambient_agents)](https://api.reuse.software/info/github.com/reznikmm/ambient_agents)

An Ada 2022 port of the Ambient Agents workshop. The workshop starts with
a chat agent that can use tools, then adds background work triggered by
GitHub activity and timers. This repository contains the Step 1 chat loop
and the Step 0 signal simulator.

## Run Step 1

Install [Alire](https://alire.ada.dev/) and use a GNAT toolchain with Ada 2022
support. The console uses `curl` for HTTP and HTTPS. Run this from the
repository root with a tool-capable Chat Completions model.

```sh
export CHAT_COMPLETIONS_URL=http://localhost:8080/v1/chat/completions
export CHAT_COMPLETIONS_MODEL=local-model
alr run
```

Use the full endpoint URL and the model identifier your server accepts.
Set `CHAT_COMPLETIONS_API_KEY` if the server requires a key. Ask “What open
issues do we have, and which one would you pick first?” to try the local
`list_open_issues` tool, then ask a follow-up about the issue it picked.

| Console input | Effect |
| --- | --- |
| `/simulate` | Submit a sample CI failure on `main` and show the received event count |
| `/thread` | Display the visible conversation in order |
| `/reset` | Clear the conversation and the agent's signal state |
| `/quit` | Exit the application |

The console stores visible messages in `Threads.Thread`. `Sessions.Session`
is the entry point for the model-facing conversation. The simulator submits
a `Signals.Agent_Event` through `Agents.Ingest`, which records the event.
The pipeline stage interfaces are in `Prefilters`, `Gates`, `Inboxes`,
`Workers`, `Policies`, and `Timers`.

The [Step 1 prompt](prompts/step-1.md) describes the tool loop and its tests.

## Build and test

```sh
alr build
alr test
```

The tests live in the separate Alire crate under `testsuite/`. Run them
directly with `alr -C testsuite/ run`.

## Maintainer and license

Maintained by [Max Reznik](https://github.com/reznikmm). Licensed under
Apache-2.0 WITH LLVM-exception. See [LICENSES/](LICENSES/) and
[REUSE.toml](REUSE.toml).
