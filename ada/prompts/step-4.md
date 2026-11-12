# Ada workshop, step 4

Filter and gate: read Ambient.Engine.Ingest, Watch_Matches, Rule_Verdict and Gate. Drop bots, edits, green CI and self posts before the gate. Match standing watches, explain every ignore and fall back when models fail.

Build with `make build`. Run `ada/bin/ambient_evals --step 4` and
`make test` from the workshop root. Keep `fixtures/` and the original
`evals/` unchanged. Use the local MCP, ACP and Chat Completions libraries;
never hand-edit their generated bindings. Follow the Ada conventions in their
AGENTS.md files. Select behavior using `WORKSHOP_STEP=4` or the stage's
Load control. These controls preserve your source edits.
