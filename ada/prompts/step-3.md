# Ada workshop, step 3

The naive pipeline: read Ambient.Engine.Ingest, Flush and Work. Select step 3, replay the storm, and inspect why every signal starts a worker and sends a report.

Build with `make build`. Run `ada/bin/ambient_evals --step 3` and
`make test` from the workshop root. Keep `fixtures/` and the original
`evals/` unchanged. Use the local MCP, ACP and Chat Completions libraries;
never hand-edit their generated bindings. Follow the Ada conventions in their
AGENTS.md files. Select behavior using `WORKSHOP_STEP=3` or the stage's
Load control. These controls preserve your source edits.
