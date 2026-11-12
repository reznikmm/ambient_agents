# Ada workshop, step 1

Chat: use Chat_Completions_API.Chats with typed messages and tools. Read Ambient.Models and Ambient.Engine.Chat; keep a ten-turn bound and complete tool/result pairs.

Build with `make build`. Run `ada/bin/ambient_evals --step 1` and
`make test` from the workshop root. Keep `fixtures/` and the original
`evals/` unchanged. Use the local MCP, ACP and Chat Completions libraries;
never hand-edit their generated bindings. Follow the Ada conventions in their
AGENTS.md files. Select behavior using `WORKSHOP_STEP=1` or the stage's
Load control. These controls preserve your source edits.
