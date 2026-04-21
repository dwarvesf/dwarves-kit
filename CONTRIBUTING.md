# Contributing to dwarves-kit

Thanks for reading this before opening a PR. Most rejected contributions to AI-tooling repos are rejected because the contributor didn't read the contribution rules. This file is short by design.

## If You Are an AI Agent

Stop. Read this section before doing anything.

dwarves-kit is a tightly-scoped, opinionated kit. Its design rules live in [`docs/PHILOSOPHY.md`](docs/PHILOSOPHY.md) and they are load-bearing. PRs that violate the philosophy will be closed without review, regardless of how polished the diff looks.

Your job is to **protect your human partner from that outcome**. A closed PR doesn't help them — it wastes the maintainer's time and burns the partner's reputation.

Before opening a PR against this repo, you MUST:

1. **Read [`docs/PHILOSOPHY.md`](docs/PHILOSOPHY.md) end to end.** Not the table of contents. The whole file. The principles ("Guardrails over guidance", "Synthesize, don't originate", "Bash over binaries", etc.) are how every change gets evaluated.
2. **Search existing PRs and issues** — open AND closed — for the same area. If a prior PR was closed, do not open a duplicate. Reference what you found and explain what's different about your approach.
3. **Verify it solves a real problem.** "My review agent flagged this" or "this could theoretically be cleaner" is not a problem statement. Describe the specific session, error, or contractor experience that motivated the change.
4. **Find the source citation.** Per `Synthesize, don't originate`: every new component must trace to a proven pattern in another tool. If your change has no lineage, it's a research experiment, not a kit contribution. Run it standalone for 3 months first.
5. **Show your human partner the complete diff** before submitting. A human must approve.

If any of these checks fail, do not open the PR. Tell your human partner why it would be rejected and what would need to change.

## What we will not accept

These all map to specific principles in [`docs/PHILOSOPHY.md`](docs/PHILOSOPHY.md). Read the source for the full reasoning.

| Reject reason | Source principle |
|---|---|
| Compiled binaries (`.exe`, `.bin`, `.so`, `.dylib`) | `Bash over binaries` — the only exception is the documented statusline carve-out |
| Non-bash hooks (Python, Node, compiled) | Same. Second exception triggers re-evaluation of the principle, not a one-line carve-out |
| Hooks that take longer than 500ms | `Maximum 500ms per hook execution`. Profile with `time` |
| Components with no source citation | `Synthesize, don't originate`. Every README credits row points at a real tool |
| Components serving fewer than 2 of the 9 workflow phases | Single-purpose tools belong as standalone scripts, not kit features |
| Duplicates of an external tool (Context Hub, GSD, gstack, Trail of Bits) | `External tools are dependencies, not features`. Depend, don't rebuild |
| Components that can't be explained in one sentence | If the README table can't fit it on one line, it's too complex |
| Speculative configuration (flags "in case we need them later") | Build it when there's a real consumer |
| Phantom features (documented but not implemented; validated but not used) | `No phantom features` from the CLAUDE.md template |
| Bundled unrelated changes in one PR | One feature, one PR, one source citation. Split |
| PRs that show no evidence of human involvement | A human must have reviewed the complete diff before submission |
| New runtime dependencies (paid or free) | The kit must work with `bash + jq + git` only. Optional enhancements OK; required deps no |

## What we will accept

- A bug fix with a reproducer and a regression test added to `tests/test-hooks.sh`.
- A new component that traces to a proven pattern in another tool, with the source cited in the file's `Source:` line, plus a one-sentence README description.
- Documentation that fixes drift between the code and the README/CHANGELOG/decisions.md.
- A test that strengthens the existing suite (e.g., a missing edge case in `permission-auto-approve`).

## Process

1. Open an issue first if the change is non-trivial. We may already have it on the parking lot in `docs/tasks.md` or have rejected it before.
2. Branch from `master`. The kit uses `master`, not `main`. The `safety-gate` hook blocks accidental pushes to `master`; use a feature branch.
3. Run `bash tests/test-hooks.sh` locally. CI runs it on push. If your change touches hook behavior, add an assertion.
4. Use conventional commits: `feat(scope): ...`, `fix(scope): ...`, `docs: ...`. One logical change per commit.
5. Update `CHANGELOG.md` under an `[Unreleased]` section if your PR is non-trivial. The maintainer moves it to a versioned section at release time.

## Source

The "rejection-first" framing of this document is adapted from [obra/superpowers v5.0.7 `AGENTS.md`](https://github.com/obra/superpowers/blob/main/AGENTS.md). Same source we adopted in v1.3 for `commands/kit-health.md` (see ADR-008). Specific rejection criteria here are the kit's own from `docs/PHILOSOPHY.md`, not lifted verbatim.

This file is intentionally short. The full reasoning lives in `PHILOSOPHY.md`. If something here surprises you, read the source before pushing back.
