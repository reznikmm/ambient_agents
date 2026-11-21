Ambient_Agents
========

[![Build with Alire](https://github.com/reznikmm/ambient_agents/actions/workflows/alire.yml/badge.svg)](https://github.com/reznikmm/ambient_agents/actions/workflows/alire.yml)
[![REUSE status](https://api.reuse.software/badge/github.com/reznikmm/ambient_agents)](https://api.reuse.software/info/github.com/reznikmm/ambient_agents)

Ada project ambient_agents packaged as an Alire crate.

## What Is Included

This repository is a minimal starting point for an Ada 2022 library project with:

- a library crate in the repository root
- a separate testsuite crate in `testsuite/`
- CI workflows for build/test (`alire.yml`) and REUSE compliance (`reuse.yml`)
- SPDX and [REUSE](https://reuse.software/) metadata (`REUSE.toml`, `LICENSES/`)
- helper script `rename.sh` to rename ambient_agents identifiers in copied projects

Key directories and files:

- `source/` - library units (`Ambient_Agents` package)
- `ambient_agents.gpr` - root GPR project file for the library
- `alire.toml` - root crate metadata and test action
- `testsuite/` - separate Alire crate for tests
- `AGENTS.md` - repository-specific instructions for coding agents

## Requirements

- [Alire](https://alire.ada.dev/)
- GNAT toolchain compatible with Ada 2022

## Build And Test

From repository root:

```sh
alr build
alr test
```

Run testsuite crate directly:

```sh
alr -C testsuite run
```

## Using This Ambient_Agents

1. Create a new repository from this ambient_agents.
2. Run `./rename.sh <your_project_name>` to rename `ambient_agents`/`Ambient_Agents`/`AMBIENT_AGENTS` identifiers.
3. Adjust crate metadata in `alire.toml`.
4. Replace `source/ambient_agents.ads` with your actual library units.

Use `./rename.sh --dry-run <your_project_name>` to preview changes.

## Maintainer

[Max Reznik](https://github.com/reznikmm)

## License

Licensed under Apache-2.0 WITH LLVM-exception. See `LICENSES/` and `REUSE.toml`.

