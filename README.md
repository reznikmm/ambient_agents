# Ambient agents workshop in Ada

The workshop runtime is ported to Ada 2022, using the sibling `mcp/`, `acp/`
and `chat_completions_api/` libraries. The browser app and presentation pages
remain HTML/JavaScript. Node, TypeScript, and pnpm are unnecessary for the Ada runtime.
The original TypeScript sources, fixtures, and tags are retained as a reference;
[their workshop guide is here](README-typescript.md).

```text
chat -> Chat_Completions_API -> tools -> main thread
GitHub / simulator / clock -> prefilter -> gate -> inbox
  -> per-signal sessions -> policy -> thread / 09:00 UTC digest
                                  -> Markdown memory
MCP stdio -> the same tools        ACP v2 -> external worker agent
```

## Build and run

The launch scripts target Linux. Requires Alire with GNAT supporting Ada 2022,
Bash, GNU `timeout`, and `curl`.
Tests additionally use `jq`, `rg`, and OpenSSL. Real GitHub polling uses `gh`.
The three sibling libraries must be next to this repository; Alire pins them
locally and resolves their VSS dependencies.

```sh
make build
make eval                    # unchanged 60-event fixture, six Ada evaluations
make test                    # all nine steps and offline integration tests
./ada/run.sh                 # http://127.0.0.1:4100
```

Without model credentials the simulator, rules gate, policy, timers, memory,
webhooks, and evaluations work. For chat, copy `.env.ada.example` to `.env.ada`
and configure an OpenAI-compatible endpoint and model. The launch scripts source
that file; direct binary invocations use exported environment variables.

```sh
CHAT_COMPLETIONS_URL=http://127.0.0.1:8080/v1/chat/completions \
CHAT_MODEL=local-model ./ada/run.sh

WORKER_MODE=model ./ada/run.sh    # structured planning, no worker tools
WORKER_MODE=acp ACP_AGENT=/absolute/path/to/adapter ./ada/run.sh
./ada/run.sh --mcp               # newline-delimited MCP on stdin/stdout
./ada/run.sh --replay fixtures/storm.json
```

`OPENAI_API_KEY`, `OPENROUTER_API_KEY`, and `AI_GATEWAY_API_KEY` are supported.
An explicit `CHAT_COMPLETIONS_URL` takes precedence. `CHAT_MODEL`, `GATE_MODEL`,
and `WORKER_MODEL` select models. `GATE_MODE` is `rules`, `model`, or `decision`;
the latter supports Jev, Clef, and Clef-Flash and falls back to model/rules.
Provider keys and model access are unnecessary for tests.

## Run the talk

```sh
make start                   # naive :4101, finished :4102, stage :4103,
                             # presentation/dashboard :4000
make stop
```

Each process has separate state and memory under `.data/ada/`. The stage's
**Load step-N** control selects behavior in the Ada program and resets its
runtime state; it does not check out old TypeScript tags or discard source edits.
The stage evaluates the selected step using the Ada evaluation executable.

| Step | Behavior added | Passing evaluations |
|---|---|---|
| 0–2 | Scaffolding, chat, GitHub input | 0/6 |
| 3 | Every event starts work | 0/6 |
| 4 | Prefilter and watch gate | 2/6 |
| 5 | Duplicate IDs and five-minute subject/kind suppression | 3/6 |
| 6 | Signal sessions, policy, ping budget, Yes/No answers | 5/6 |
| 7 | Wakeups, reminders, daily digest | 6/6 |
| 8 | Worker results in Markdown memory | 6/6 |

Ada exercises are in `ada/prompts/`. You can also select a step with
`WORKSHOP_STEP=0..8`, or `POST /api/step` with `{"step":4}`. The original
`prompts/`, `pnpm` commands, and worktree scripts still describe the TypeScript
reference.

## Protocols and state

- **Chat Completions:** typed requests and responses through your library;
  up to ten model/tool turns, with recent conversation kept at user boundaries.
  Responses use the app's NDJSON format. The library currently returns whole
  completions, so token-by-token streaming is unavailable.
- **MCP:** the `2026-07-28` draft pinned by `mcp/`, including `server/discover`,
  `tools/list`, and `tools/call`. Requests carry protocol version and client
  capabilities in `_meta`, as in the library demos. The catalog exposes checkout
  reads/search, GitHub reads, skills, watches, reminders, and memory tools.
  `github_comment` is enabled only with `CHAT_CAN_COMMENT=1` and `GITHUB_REPO`.
- **ACP:** the v2 draft pinned by `acp/`. One external adapter process maintains
  sessions by signal. The client waits for idle after prompt acceptance, assembles
  message chunks and replacement updates, resumes stored sessions after restart,
  and declines permission requests. Adapter installation is documented in the
  sibling `acp/demos/claude/` and `acp/demos/codex/` guides. `ACP_AGENT` must be an
  executable; use a wrapper for arguments and adapter-specific environment.
  `WORKER_MODE=claude` is an alias for ACP; `auto` uses ACP for GitHub events and
  simulates other events.
- **GitHub:** HMAC-SHA256 webhook verification is native Ada, including ping
  deliveries. Polling bootstraps existing items and shares event IDs with webhooks.
- **Persistence:** `.data/agent.json` is replaced atomically. It stores sessions,
  duplicate IDs, handled times, pending approvals, notifications, wakeups, and the
  main thread. It is separate from the TypeScript SQLite database. UTC is used
  for daily budgets and the 09:00 digest. `STATE_PATH` and `MEMORY_DIR` override
  locations. A state file belongs to one process.

The runtime serializes event processing and worker turns. This preserves subject
ordering and bounds worker activity, but a slow model/ACP turn also delays HTTP
requests. Simulated workers finish immediately; `SIM_SPEED` scales gate batching.
Memory is local Markdown; the TypeScript Daytona SDK integration is not included.
Presentation decision races execute requests serially and report measured elapsed
times; they are demonstrations, not parallel throughput benchmarks. The decision
page retains the reference's Clef price estimates; it does not fetch live prices.

## Source map

| Ada unit | Responsibility |
|---|---|
| `Ambient.Engine` | Event pipeline, inbox, sessions, policy, timers, tools, chat |
| `Ambient.Types` | Normalized events, worker results, statistics |
| `Ambient.State` | Atomic JSON store, watches, Markdown memory |
| `Ambient.Models` | Chat Completions client and curl HTTP transport |
| `Ambient.ACP_Client` | Typed ACP v2 stdio client and streamed session updates |
| `Ambient.MCP_Server` | Typed MCP dispatch sharing the chat tool catalog |
| `Ambient.Sources` | Signed GitHub webhooks, poller, simulator |
| `Ambient.Decisions` | Decision providers and presentation playground |
| `Ambient.Server` | Loopback HTTP API, SSE, dashboard and stage routes |
| `Ambient.JSON`, `Ambient.Codecs` | VSS JSON and generated protocol codec adapters |

Ada presentation chapters and the start page are in `ada/app/`; they reuse the
browser rendering code in `dashboard/`.

`make format` formats only this project's Ada sources. `make test` checks all
step scores and exercises HTTP, signatures, approval answers, Unicode memory,
path confinement, persistence, SSE, MCP, ACP permissions/session reuse, and a
Chat Completions tool round trip against local fixtures. It never calls a live
model or posts to GitHub/Slack. The original `evals/` and `fixtures/` are unchanged.
