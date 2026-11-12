# Ambient agents workshop

The default implementation is now Ada 2022 in `ada/`, using locally pinned
sibling `mcp/`, `acp/`, and `chat_completions_api/` libraries. The original
TypeScript sources and tags are retained as reference; see README-typescript.md.
The browser app and presentation remain HTML/JavaScript.

## Build and check

- `make build`: compile the Ada program and evaluation executables.
- `make eval`: six behavioral checks using unchanged fixtures/storm.json.
- `make test`: all nine step scores and offline protocol/HTTP tests.
- `make format`: GNATformat, without formatting dependency projects.
- `make run`: agent on localhost:4100; `make start` / `make stop`: the talk.
- Run binaries from the repository root so assets and skills resolve correctly.

## Map

- `ada/src/ambient-engine.*`: pipeline, inbox, policy, timers, shared tools/chat.
- `ada/src/ambient-models.*`: typed Chat Completions and HTTP transport.
- `ada/src/ambient-acp_client.*`: ACP v2 worker sessions and streaming updates.
- `ada/src/ambient-mcp_server.*`: pinned MCP draft stdio tools.
- `ada/src/ambient-sources.*`: signed webhooks, GitHub polling, simulator.
- `ada/src/ambient-state.*`: JSON persistence and local Markdown memory.
- `ada/src/ambient-server.*`: HTTP/SSE and presentation APIs.
- `ada/tests/`: Ada evaluations and Bash/jq integration fixtures.
- `ada/prompts/`: Ada exercises. `prompts/` describes the TypeScript reference.
- `app/`, `dashboard/`: shared browser assets.
- `.ruler/skills/`: worker instructions, loaded by the Ada runtime.

## Rules

- Read coding preferences in the sibling mcp/AGENTS.md or acp/AGENTS.md.
- Ada 2022; predefined containers; no Indefinite containers or unnecessary
  subtype conversions. Use descriptive names and GNATformat.
- Read package specifications before changing bodies. Keep generated dependency
  bindings untouched; regenerate in their own projects when needed.
- Keep protocol logic in Ada. Bash is for launchers and process/file orchestration.
- Do not swallow exceptions with null handlers. Include useful context in errors.
- MCP stdout contains JSON-RPC only; diagnostics go to stderr.
- All event sources enter through Agent.Ingest. Keep fixtures/ and the original
  evals/ unchanged; never weaken evaluations to pass.
- Workers never merge, close, delete or push. Comments end with
  `<!-- ambient-agent -->`. ACP permission requests are declined.
- State files belong to one process. Keep state, memory, ports and registry
  entries separate when running multiple instances.
- No live model, GitHub or Slack access in tests. Test adapters/HTTP fixtures are
  local and deterministic.
- Edit these instructions in `.ruler/`, then run `scripts/ruler.sh`; generated
  agent instruction files are not edited by hand.
