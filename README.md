# Ambient Agents in Ada

[![Build with Alire](https://github.com/reznikmm/ambient_agents/actions/workflows/alire.yml/badge.svg)](https://github.com/reznikmm/ambient_agents/actions/workflows/alire.yml)
[![REUSE status](https://api.reuse.software/badge/github.com/reznikmm/ambient_agents)](https://api.reuse.software/info/github.com/reznikmm/ambient_agents)

An Ada 2022 port of the Ambient Agents workshop. The workshop starts with
a chat agent that can use tools, then adds background work triggered by
GitHub activity and timers. This repository currently contains the step 0
console scaffold.

## Run step 0

Install [Alire](https://alire.ada.dev/) and use a GNAT toolchain with Ada 2022
support. Run this from the repository root.

```sh
alr run
```

Type a message to see the placeholder chat reply. Step 0 runs locally without
a model server or an API key.

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

## Build step 1

Give [the step 1 prompt](prompts/step-1.md) to your coding agent. It adds a
model-backed conversation and a local demo tool using
[`chat_completions_api`](https://github.com/reznikmm/chat_completions_api).
The prompt describes provider configuration, the tool loop, and its tests.

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
