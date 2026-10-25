# dwarves-kit

[![CI](https://github.com/dwarvesf/dwarves-kit/actions/workflows/test.yml/badge.svg)](https://github.com/dwarvesf/dwarves-kit/actions/workflows/test.yml)
[![Version](https://img.shields.io/github/v/tag/dwarvesf/dwarves-kit?label=version)](https://github.com/dwarvesf/dwarves-kit/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/Claude_Code-plugin-blue)](https://code.claude.com)

dwarves-kit adds a spec-driven workflow to Claude Code: you set the goal and the gates, and agents build and fix inside them.
A read-only verifier decides when work is done, so no agent grades its own homework.
Safety is mechanical: bash hooks block a force push, a secret read, or a ship with no proof, and a fix loop stops after two tries and asks you.

![One change moves through think, spec, execute, review, docs, ship, wrap and retro; the verification pipeline and the ship-gate block, the other gates advise](docs/figures/loop.png)

_Figure: one change moves through eight phases; two gates block, the rest advise, and each retro feeds the next think._

## Install

```
/plugin marketplace add dwarvesf/dwarves-kit
/plugin install kit@dwarves-marketplace
```

Open your repo and run `/kit:onboard`. It adopts the repo and picks modules, and it previews every write; a decline changes nothing.
Then run `/kit:start` at the top of each session. It reads where the repo stands and names the next command.

No Claude Code plugin system, or you use Codex? See [Install options and modules](docs/MANUAL.md#install-options-and-modules) for the bash installer, the Codex adapter and the requirements.

## Pick your path

| You want to | Read |
|---|---|
| See the whole loop once, start to finish | [`docs/QUICKSTART.md`](docs/QUICKSTART.md) |
| Try the kit on a repo, and know what it writes | [`docs/guides/adopt.md`](docs/guides/adopt.md) |
| Ship one change and see what happens when | [`docs/guides/spine.md`](docs/guides/spine.md) |
| Get a change reviewed before it ships | [`docs/guides/review.md`](docs/guides/review.md) |
| Run several pieces of work at once | [`docs/guides/mega-goal.md`](docs/guides/mega-goal.md) |
| Check that your docs work for a stranger | [`docs/guides/gauntlet.md`](docs/guides/gauntlet.md) |
| Land a finished session and clean up | [`docs/guides/wrap.md`](docs/guides/wrap.md) |
| Fix a push that was blocked | [`docs/guides/gates-and-proof.md`](docs/guides/gates-and-proof.md) |
| Hunt a bug | [`docs/guides/debug.md`](docs/guides/debug.md) |
| Contribute to the kit | [`CONTRIBUTING.md`](CONTRIBUTING.md) |

Every guide: [`docs/guides/README.md`](docs/guides/README.md).

You rarely type a command. Say what you want, such as "add a `--version` flag to the CLI", and the kit sizes the work, writes the spec, builds, verifies, and stops only where it needs your call.

## What is in the box

- **Commands.** The `/kit:*` actions for each phase. Every command is documented in the [command reference](docs/MANUAL.md#command-reference-the-kit-invokes-these-from-your-intent-you-rarely-type-them).
- **Agents.** Read-only verifiers and reviewers, plus a fix-agent and domain builders. The [agents table](docs/MANUAL.md#agents-dispatched-not-invoked) says who dispatches each.
- **Hooks.** Bash scripts on Claude Code events. A small spine always runs; the rest is opt-in. The full inventory is [`docs/hooks.md`](docs/hooks.md).
- **Skills.** Claude loads these when your intent matches, for example the audit loops. See [Skills](docs/MANUAL.md#skills-claude-triggered).
- **The bash engine.** Each subsystem is a standalone shell command under `bin/`, for example `bash bin/board --help` and `bash bin/precedent find "<query>"`. It runs without Claude Code.

## Who it is for

A lead who hands implementation to contractors on one shared spec, and anyone who spends long days in Claude Code and wants guardrails and a record of what ran.
It is bash and markdown, with no UI and no server. It targets one engineer or one lead with helpers, not teams that need cross-machine orchestration; [`docs/MANUAL.md`](docs/MANUAL.md#who-this-is-for) says where that line sits.

## Learn more

| Doc | What it holds |
|---|---|
| [`docs/MANUAL.md`](docs/MANUAL.md) | The operator reference: commands, agents, skills, install layers, project layout, tests, troubleshooting |
| [`docs/hooks.md`](docs/hooks.md) | Which hook prints which message, and the knobs that tune it |
| [`docs/architecture.md`](docs/architecture.md) | How the parts fit and how data moves |
| [`docs/SYSTEM-DESIGN.md`](docs/SYSTEM-DESIGN.md) | The design model: use cases, components, flows, state machines |
| [`docs/FEATURES.md`](docs/FEATURES.md) | Generated one-row-per-feature registry |
| [`docs/PHILOSOPHY.md`](docs/PHILOSOPHY.md) | Why the kit is shaped this way, and what it rejects |
| [`docs/CHANGELOG.md`](docs/CHANGELOG.md) | Release history |
| [`CONTRIBUTING.md`](CONTRIBUTING.md), [`SECURITY.md`](SECURITY.md), [`LICENSE`](LICENSE) | Contribute, report a vulnerability, MIT terms |
