# Ada workshop, step 2

GitHub input: read Ambient.Sources.From_Webhook, Verify_Signature and GitHub_Poller. All sources produce Ambient.Types.Agent_Event through Agent.Ingest. Verify HMAC before ingesting.

Build with `make build`. Run `ada/bin/ambient_evals --step 2` and
`make test` from the workshop root. Keep `fixtures/` and the original
`evals/` unchanged. Use the local MCP, ACP and Chat Completions libraries;
never hand-edit their generated bindings. Follow the Ada conventions in their
AGENTS.md files. Select behavior using `WORKSHOP_STEP=2` or the stage's
Load control. These controls preserve your source edits.
