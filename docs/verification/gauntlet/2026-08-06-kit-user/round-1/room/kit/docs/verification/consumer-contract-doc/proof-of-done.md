# Proof of done: consumer-contract-doc (harness-ops sub-goal 07)

Lane: full · rid: `harness-ops-07-contract-doc` · Type: docs (docs-only, no code change)

## Acceptance criteria

| # | Criterion (from `Done =`, goal 07) | Met |
|---|---|---|
| A1 | `docs/consumer-contract.md` exists | yes |
| A2 | It names the 4 adopt-injected files (AGENTS.md copy, CLAUDE.md kit-block, WORKFLOW.md pointer, docs/verification/README.md marker) | yes |
| A3 | It documents the `KIT_LEDGER_DIR` knob (shared vs per-project) | yes |
| A4 | It documents the optional `<project>/.kit.toml` override (SPEC-192) | yes |
| A5 | It documents the stable `bin/` entrypoint (SPEC-184) | yes |
| A6 | Doc-vs-code check: the doc's named file list matches exactly what `lib/adopt.sh` injects | yes (captured below) |

## Implementation

- `docs/consumer-contract.md`: one skimmable page, table-first. Sourced directly from
  `lib/adopt.sh` (the 4-file inject + the `.kit.toml`/settings.json mechanism),
  `lib/telemetry/kit-log-dir.sh` (the `KIT_LEDGER_DIR` precedence), `SPEC-192-project-override.md`
  (the `.kit.toml` seed/wire loop), and `SPEC-184-stable-consumer-interface.md` (the `bin/`
  forwarders).
- No code touched. Scope per the goal: `docs/consumer-contract.md` only; adopt mechanics and
  the config schema stay owned by goals 05/06.

## Doc-vs-code check (run verbatim)

`lib/adopt.sh`'s own numbered comments are the ground truth for what it injects:

```
$ grep -n '^# [0-9]\. ' lib/adopt.sh
57:# 1. AGENTS.md -- the operate-contract. NEVER overwritten (even on --refresh).
64:# 2. WORKFLOW.md pointer -- create if absent; --refresh overwrites to current. Write atomically
72:# 3. CLAUDE.md loader (@AGENTS.md import) -- append once; --refresh replaces the managed block.
90:# 4. proof marker -- presence opts this repo into the ship-gate. NEVER overwritten.
```

`docs/consumer-contract.md`'s "The 4 files `/kit:adopt` injects" table lists, in the same
order: `AGENTS.md`, `CLAUDE.md` (managed block), `WORKFLOW.md`, `docs/verification/README.md`.
One-to-one match against adopt.sh's numbered steps 1-4. No drift.

Everything adopt.sh does AFTER step 4 (`.kit.toml` seed, `.claude/settings.json` hook wiring)
is documented separately in this page under "The optional `.kit.toml` override", explicitly
called out as opt-in / not part of the base 4-file contract, matching the goal's own framing
("the 4 adopt-injected files ... the `KIT_LEDGER_DIR` knob ... the optional `.kit.toml`
override" as three distinct things).

## Confirmation run-table

| Check | Command | Result |
|---|---|---|
| Doc exists | `test -f docs/consumer-contract.md` | PASS |
| Doc-vs-code (adopt's 4 injected files == doc's named 4 files) | `grep -n '^# [0-9]\. ' lib/adopt.sh` vs. the doc's file table | PASS (see above) |
| Gate ledger check (full lane) | `bash lib/gate/gate-ledger.sh check full harness-ops-07-contract-doc` | exit 0 |

## Reproduce

```
cd dwarves-kit
grep -n '^# [0-9]\. ' lib/adopt.sh
cat docs/consumer-contract.md
bash lib/gate/gate-ledger.sh check full harness-ops-07-contract-doc
```

## Deviations from the goal contract

- The goal text said "Classify... (expect normal)". `bash lib/classify/lane-classify.sh
  classify "..."` actually returned `full`. Recorded gates for the full-lane required set;
  three (design-critique, spec, test-plan) are genuinely inapplicable to a one-page docs
  artifact with `Design: obvious` and were recorded as human overrides with reasons rather
  than silently skipped, so `gate-ledger.sh check full` passes honestly.
- No SPEC-193 was written: the goal file itself (`_meta/megagoals/harness-ops/goals/
  07-consumer-contract-doc.md`) is the spec-of-record for this docs-only change; the goal's
  own Scope explicitly excludes re-documenting adopt mechanics or the config schema (those
  already have SPEC-192/SPEC-184), so there was no new design surface to spec.
