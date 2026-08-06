# Spec: /kit:adopt (one-command per-repo adoption of the operate-contract)

Status: DRAFT
Lane: full (lane-classify said `normal`; overridden, see implementation-notes/kit-adopt-command.md)

## Problem

The kit's orchestration is real but does not self-install. `install.sh` only prints a tip
("copy AGENTS.md to your repo root"), so consumer repos silently lack the operate-contract: no
AGENTS.md telling the agent to classify + pick a lane, no proof marker that makes the ship-gate
engage, no CLAUDE.md pointer (Claude Code auto-loads CLAUDE.md, not AGENTS.md). The result, seen
live in the growatt-tui session in ops-toolkit: a full-lane change shipped review-less because the
right-arm gates were never wired and the lane arm fails open with no lane. The classifiers
(`lane-classify`, `task-type-classify`, `proof-gate`) already exist; what is missing is the
per-repo trigger that makes an agent use them.

## Design

### Approaches considered

- **A new `/kit:adopt` command + a thin `lib/adopt.sh` driver (chosen).** The command is
  agent-invokable and re-runnable; the driver does the idempotent file injection so it is
  testable headless. Tradeoff: one more command + lib file.
- **Extend `install.sh` only.** Rejected: install runs once at kit-install time, not per-repo,
  and is not agent-invokable mid-session; adoption must be a first-class, re-runnable action.
- **Copy the whole kit (AGENTS.md + WORKFLOW.md 49KB + lib) into each repo.** Rejected:
  duplicates the engine, drifts, and the classifiers already run from the installed kit. The
  consumer needs the contract + pointers, not a fork.

### Chosen design

`/kit:adopt [<target>] [--check]` (default target = repo root). The command shells to
`lib/adopt.sh` which idempotently ensures, in `<target>`:

1. **`AGENTS.md`**, the operate-contract. Copied from the kit if absent; never overwritten
   (`--merge` semantics). This is what tells the agent "read in this order, classify, pick a lane".
2. **`CLAUDE.md` loader pointer**, appended once (grep-guarded) so Claude Code, which auto-loads
   CLAUDE.md but not AGENTS.md, is pointed at AGENTS.md + the installed kit. Idempotent.
3. **`WORKFLOW.md` pointer doc**, a short local file pointing at the installed kit's WORKFLOW.md
   (the lane x phase matrix the gate-ledger reads from the kit, not the consumer). Not the 49KB copy.
4. **`docs/verification/README.md` proof marker**, created if absent, so the ship-gate's
   proof + lane arms ENGAGE in this repo (the gate is opt-in via this marker).

"Wiring the classifiers" = the injected AGENTS.md + CLAUDE.md reference the installed kit's
`lib/{lane-classify,task-type-classify,proof-gate}.sh` (resolved via `CLAUDE_PLUGIN_ROOT` or
`~/.claude/dwarves-kit`), so an adopted repo's task resolves to its lane + loop-type + proof
artifact. The consumer copies no lib.

### Interfaces

- Input: a target dir (default `.`). `--check` reports adoption status without writing (exit 0
  adopted / 1 not). No other flags in v1.
- Output (writes): the four artifacts above, each created only if absent (idempotent). Re-run on
  an adopted repo writes nothing (clean `git diff`).
- Invariant: never overwrite an existing AGENTS.md / CLAUDE.md / proof marker (non-destructive);
  a partially-adopted repo converges to fully-adopted on re-run without clobbering.

## Scope

**In:** `commands/adopt.md`, `lib/adopt.sh`, a test under `tests/`, the four-artifact injection,
the CLAUDE.md pointer block content.
**Out:** the ship-gate fail-closed change + install.sh rewrite (sub-goal 02 / SPEC-048); adopting
any real repo (sub-goal 03).
**Not:** rebuilding the classifiers or changing the lane / proof-class taxonomy; a `--override`
destructive mode; copying lib/ or the full WORKFLOW.md into consumers; multi-runtime portable
enforcement (v3.x); a config DSL.

## Acceptance criteria

- [ ] `bash lib/adopt.sh <tmp-repo>` creates AGENTS.md + a WORKFLOW pointer + a CLAUDE.md loader
  line + `docs/verification/README.md` in a fresh git repo.
- [ ] A second run is a clean no-op (`git -C <tmp> diff --quiet` after re-run).
- [ ] From the adopted repo, `proof-gate.sh contract "<task>"` resolves two different task
  descriptions ("add a data-pull CLI command" vs "benchmark X vs Y") to two different artifacts.
- [ ] `bash lib/adopt.sh --check <tmp>` exits 0 on an adopted repo, 1 on a fresh one.
- [ ] Never overwrites a pre-existing AGENTS.md / CLAUDE.md (write a sentinel, re-run, assert
  the sentinel survives).
- [ ] `commands/adopt.md` exists with the `--- description ---` front-matter (mirrors start.md).
- [ ] `bash tests/test-adopt.sh` passes; the existing suite (`bash tests/test-meta.sh`) stays green.

## Test plan

| Scenario | Assert | Control |
|---|---|---|
| fresh repo adopt | 4 artifacts present | a non-adopted repo lacks them |
| re-run idempotency | clean git diff on 2nd run | (the negative: a non-idempotent impl dirties the tree) |
| no-clobber | pre-seeded AGENTS.md sentinel survives | absent the guard, it would be overwritten |
| classifier reachable | proof-gate resolves 2 task types to 2 artifacts | a wrong wiring resolves both to the same / errors |
| --check | exit 0 adopted / 1 fresh | inverted exit = broken |

Behavioral proof (proof-gate=behavioral): record a live `lib/adopt.sh` run on a temp repo +
the no-clobber negative control in `docs/verification/kit-adopt.md`.

## Edge cases

1. Target already fully adopted -> no-op, exit 0.
2. Target partially adopted (has AGENTS.md, lacks marker) -> adds only the missing pieces.
3. Target is not a git repo -> still injects files (adoption is filesystem-level), but warns.
4. `CLAUDE.md` exists without the pointer -> append the pointer block once; existing content untouched.
5. Installed-kit path unresolved (`CLAUDE_PLUGIN_ROOT` unset + no `~/.claude/dwarves-kit`) ->
   fail loud with the expected path, do not write half a contract.

## Resolved decisions (during build)

- (append here as build surfaces them)
