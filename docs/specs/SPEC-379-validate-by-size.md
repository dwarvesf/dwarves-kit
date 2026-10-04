# Spec: validate by size (run the 7-lens round only on large specs)

Generated: 2026-10-01
Status: DRAFT
Lane: full (kit.toml is a hard path; weakens validation on small normal-lane specs)
Depth: standard (prose rules in command docs, one lane-data line, one small helper verb; no unknown a probe would close)
References: `commands/spec.md` step 5, `commands/execute.md` validation preflight, `commands/battery.md` leg 2, `kit.toml` `[lane.normal]`, `docs/WORKFLOW.md` lane x phase table
Source: operator approved the design in session 2026-10-01; evidence from the 2026-09-30 wrap wave retro

## Problem

The 7-reviewer validation round costs one Opus and six Sonnet runs per spec. In the 2026-09-30 wrap wave every HIGH defect was caught by the post-build review lens, none by spec validation. The validation criticals worth having (SPEC-374, SPEC-363) came from large full-lane specs. A small normal-lane spec pays the round and gets nothing the post-build review does not also catch. The battery review leg also runs on Opus on the normal lane, where a Sonnet reviewer with the same lens set suffices.

## Rules

| # | Rule | Lands in |
|---|---|---|
| S1 | A spec is SMALL when its lane is `normal`, its `Depth:` is `standard` (absent counts as standard), and it has at most 3 tasks. Everything else is LARGE. A spec with no countable task is LARGE. `bash lib/spec/spec.sh depth size <spec>` prints `small` or `large` and exits 0 or 1. | `lib/spec/spec-depth.sh`, `commands/spec.md` |
| S2 | `/kit:spec` step 5 and the `/kit:execute` preflight run the parallel 7-reviewer round only for LARGE specs. For a SMALL spec the lead records `gate-ledger.sh override <rid> Validate "small spec: normal lane, standard depth, N tasks; post-build review covers it"` and moves on. The operator can always ask for a round. | `commands/spec.md`, `commands/execute.md` |
| S3 | `kit.toml` `[lane.normal]` gains `validate` in `light`, so the ship-gate stops requiring it on the normal lane. A LARGE normal-lane spec still runs the round by S2. The `docs/WORKFLOW.md` lane x phase table matches. Full, bug, backfill and tiny are unchanged. | `kit.toml`, `docs/WORKFLOW.md` |
| S4 | The battery review leg (leg 2) runs on Sonnet (mid) on the normal lane and stays Opus on the full lane. Lens escalation rules are unchanged. | `commands/battery.md` |

Boundaries:

- A hard-path diff already forces `full` at push, so S1 needs no hard-path test.
- S3 makes the gate optional on normal; the discipline comes from S2's prose plus the post-build review. A LARGE normal-lane spec that skips the round is caught by nothing mechanical. That is the accepted cost of the operator's design.
- Out of scope: the full lane's round ceiling, the critical bar, the reviewer tiers inside a round.

## Tasks

| ID | Task | Files | Done when |
|---|---|---|---|
| T1 | Add the `size` verb and its tests | `lib/spec/spec-depth.sh`, `tests/test-spec-depth.sh`, `tests/fixtures/spec-depth/` | `size` prints `small` or `large` per S1 for each boundary fixture |
| T2 | State S2 in step 5 and the preflight | `commands/spec.md`, `commands/execute.md` | both name the size check and the override line |
| T3 | Flip the normal lane data and the table | `kit.toml`, `docs/WORKFLOW.md`, `tests/test-lanes-data.sh` | `validate` is light on normal; `workflow-view` and `plan-flip` agree |
| T4 | Drop the battery review leg to Sonnet on normal | `commands/battery.md` | leg 2 names Sonnet on normal and Opus on full |
| T5 | Align the live docs that say validation always runs on normal | `docs/WORKFLOW.md`, `docs/MANUAL.md` | no live line says validation runs at every depth or on every normal spec |

## Verification

```bash
bash tests/test-spec-depth.sh
bash tests/test-lanes-data.sh
bash tests/test-meta.sh
bin/test-affected --base origin/master
grep -nP '\x{2013}|\x{2014}' docs/specs/SPEC-379-validate-by-size.md   # no output
```

Negative control: revert each rule's line (S1 verb branch, S2 wording, S3 toml line, S4 wording); the matching pin goes red, then restore.

## After state

- A small normal-lane spec records a Validate override and goes straight to the build; the post-build review is its backstop.
- A large or non-normal spec runs the parallel round exactly as today.
- The normal lane no longer requires a `validate` gate at push. Full, bug, backfill and tiny are unchanged.
- The normal-lane battery review runs on Sonnet; the full lane keeps Opus.

## Design

obvious: one counting verb beside the existing header readers, prose edits in command docs, one lane-data line; no new component, schema or irreversible choice.

## Decision Log

- 2026-10-01, operator approved the four rules in session. The validation round is skipped on that approval, recorded as `override Validate` in the gate ledger.
