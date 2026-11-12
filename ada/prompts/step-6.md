# Ada workshop, step 6

Sessions and policy: read Ambient.Engine.Work, Deliver and Ask_Answer and Ambient.ACP_Client. Keep one session per signal, obey the daily budget and preserve pending approval IDs across restarts. An answer resumes its subject without gate filtering.

Build with `make build`. Run `ada/bin/ambient_evals --step 6` and
`make test` from the workshop root. Keep `fixtures/` and the original
`evals/` unchanged. Use the local MCP, ACP and Chat Completions libraries;
never hand-edit their generated bindings. Follow the Ada conventions in their
AGENTS.md files. Select behavior using `WORKSHOP_STEP=6` or the stage's
Load control. These controls preserve your source edits.
