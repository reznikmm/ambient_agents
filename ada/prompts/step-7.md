# Ada workshop, step 7

Time: read Ambient.Engine.Schedule, Tick, Advance and Digest. Return due wakeups through Ingest; deliver personal reminders directly. Send held notifications once in the 09:00 UTC digest.

Build with `make build`. Run `ada/bin/ambient_evals --step 7` and
`make test` from the workshop root. Keep `fixtures/` and the original
`evals/` unchanged. Use the local MCP, ACP and Chat Completions libraries;
never hand-edit their generated bindings. Follow the Ada conventions in their
AGENTS.md files. Select behavior using `WORKSHOP_STEP=7` or the stage's
Load control. These controls preserve your source edits.
