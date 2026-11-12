# Ada workshop, step 8

Memory: read Ambient.State.Remember and Memory_Index and Ambient.Engine.Chat. Write worker results into journal and subject Markdown files. Include only an index in model context and read details with tools. Confine all paths to the memory root.

Build with `make build`. Run `ada/bin/ambient_evals --step 8` and
`make test` from the workshop root. Keep `fixtures/` and the original
`evals/` unchanged. Use the local MCP, ACP and Chat Completions libraries;
never hand-edit their generated bindings. Follow the Ada conventions in their
AGENTS.md files. Select behavior using `WORKSHOP_STEP=8` or the stage's
Load control. These controls preserve your source edits.
