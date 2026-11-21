# AGENTS.md

## Project scope

Ambient Agents is an Ada 2022 port of the Ambient Agents workshop. Step 0
provides a console demo, a chat stub, and in-memory signal intake. Follow the
requested workshop step and its prompt. Step 1 adds the model and tool loop.
See [prompts/step-1.md](prompts/step-1.md).

## Repository map

| Location | Responsibility |
| --- | --- |
| `source/ambient_agents-run.adb` | Console input, commands, and application wiring |
| `Ambient_Agents.Sessions` | Model-facing conversation and parts emitted for each turn |
| `Ambient_Agents.Threads` | User-visible transcript of messages and reports |
| `Ambient_Agents.Signals`, `Ambient_Agents.Agents` | Normalized events and the shared `Agents.Ingest` entry point |
| `Clocks`, `Prefilters`, `Gates`, `Inboxes`, `Workers`, `Policies`, `Timers` | Workshop clock and pipeline stage interfaces under `Ambient_Agents` |
| `prompts/` | Instructions and acceptance criteria for workshop steps |
| `testsuite/` | Separate Alire crate with the tests |
| `alire.toml`, `ambient_agents.gpr` | Root crate and executable build configuration |

Use `Signals.Agent_Event` and `Agents.Ingest` for every source, including the
simulator, GitHub, and timers. Keep model history in `Sessions.Session` and
visible messages in `Threads.Thread`. The step 1 model client is
`chat_completions_api`, with a replaceable HTTP request handler for tests.

## Ada conventions

- Follow the naming, formatting, and declaration comments in nearby code.
  Use descriptive names and Ada 2022 features where they help.
- Use `VSS.Strings.Virtual_String` for Unicode text and predefined Ada
  containers. Avoid indefinite containers and unnecessary type conversions.
- Handle exceptions with diagnostics that identify the failing operation and
  include useful context. Avoid empty exception handlers.
- Treat `alire/`, `config/`, `.obj/`, and `bin/` as generated directories.
  Make build and dependency changes in the project or crate configuration.

## Build and check

Run these commands from the repository root.

```sh
alr build
alr -C testsuite/ run
```

For a focused compile check, replace `<unit>.adb` with the Ada file to check.

```sh
alr exec -- gprbuild -q -f -c -u -gnatc -P ambient_agents.gpr <unit>.adb '-cargs:ada' -gnatef
```

Format edited Ada sources with GNATformat.

```sh
alr exec -- gnatformat --charset=utf-8 --no-subprojects -P ambient_agents.gpr
```

Read the relevant package specifications first, then inspect bodies as needed.
Keep patches focused. Compile touched units, including stage interfaces that
the executable does not yet import. For behavior changes, run the relevant
tests or CLI scenario and report what passed. Ask before a large architectural
rewrite and record any assumptions in the final update.
