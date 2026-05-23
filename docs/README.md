# docs/, the kit's design record (you do NOT need this to USE the kit)

If you just want to **use** dwarves-kit, stop here and read the repo [`README.md`](../README.md): install, then run your first `/kit:` cycle. Everything in `docs/` is the kit's own design history and dogfood output, written while building the kit. A new user never has to open it.

This folder is large because the kit was built **through its own workflow**: every feature got a spec, most got an ADR, each cycle got a retro. That accumulation is the point, not clutter, but it is for maintainers and the curious, not for getting started.

## What's here

| Path | What it is | Read it if you want to... |
|---|---|---|
| [`architecture.md`](architecture.md) | Components, data flow, the state model, the verification pipeline | understand how the pieces fit before extending the kit |
| [`PHILOSOPHY.md`](PHILOSOPHY.md) | Design principles, target user, the rejection list | know why a feature was kept out (load-bearing for contributors) |
| [`ABSORPTION.md`](ABSORPTION.md) | How the kit absorbs patterns from upstream sources | run `/kit:absorb` or audit source drift |
| `specs/` | One spec per feature (`SPEC-NNN-<slug>.md`), tracked in place via a `Status:` header | see how a feature was designed; also the kit's **live** spec store (hooks detect the active spec here) |
| `decisions/` | Architecture Decision Records, one per file (`NNNN-<slug>.md`) | understand why a choice was made, and what superseded it |
| `retro/` | Per-cycle retrospectives (output of `/kit:retro`) | learn what worked and what hurt across cycles |
| `research/` | Dated deep-scans that fed specific specs | trace a spec back to its source research |
| `absorption/` | Templates + index for the absorption workflow | work on `/kit:absorb` |

## How to read it (for maintainers)

Start with `architecture.md` for the mental model, then `PHILOSOPHY.md` for the guardrails. From there, a spec (`specs/SPEC-NNN-*.md`) is the contract for one feature and an ADR (`decisions/NNNN-*.md`) is the reasoning behind one decision; ADRs supersede each other in place (the `## Status:` line names the superseder) rather than being rewritten.
