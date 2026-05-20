# CLAUDE.md — spm

## Project

`spm` ("simple package manager") is a CLI tool for managing Python project dependencies in single-file scripts. Wraps `pip` with a focused subset of commands: `install`, `freeze`, `list`. Built for fast iteration on prototype scripts that don't justify a full `pyproject.toml`.

## Tech Stack

| Layer | Choice | Version |
|-------|--------|---------|
| Runtime | Python | 3.12 |
| Package manager | uv | latest |
| CLI framework | argparse (stdlib) | n/a |
| Testing | pytest | 8.x |
| Linting | ruff | latest |

## Commands

```bash
uv sync                  # install dependencies
uv run spm --help        # exercise the CLI
uv run pytest            # run tests
uv run ruff check .      # lint
uv build                 # build wheel
```

## Repository Structure

```
spm/
  src/spm/
    __init__.py        package init
    cli.py             argparse setup, subcommand dispatch
    commands/
      install.py       spm install <pkg>
      freeze.py        spm freeze
      list.py          spm list
  tests/
    test_cli.py        argparse + dispatch tests
    test_commands/     one test file per subcommand
  pyproject.toml       project metadata, dependencies
  README.md            user-facing docs
  CLAUDE.md            this file
  .planning/SPEC.md    active development spec
```

## Code Quality Rules

- No speculative features. The CLI does install/freeze/list. New subcommands need a justification in `.planning/SPEC.md`.
- No premature abstraction. We have 3 commands; no `BaseCommand` class until there are 6.
- Clarity over cleverness. argparse subparsers, not metaprogramming.
- Justify new dependencies. The CLI uses stdlib only at runtime; `pip` is invoked as a subprocess.
- Every command file (`install.py`, `freeze.py`, `list.py`) has an accompanying `tests/test_commands/test_<name>.py`.
- Errors from `pip` subprocess invocations are propagated with the original exit code; `spm` does not swallow them.

## Workflow

This project uses dwarves-kit. The phases, the risk-tier lanes, and the gate at each boundary are defined in the [`WORKFLOW.md`](WORKFLOW.md) contract; read it after this file.

## Spec Location

Development specs live in `.planning/`. Read `SPEC.md` before implementing any feature.
