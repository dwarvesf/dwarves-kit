# Spec: Command emit sweep -- close the RUN_REPORT under-count (kit-run-integrity sub-goal 05)

Generated: 2026-07-04
Status: VALIDATED
Lane: full (touches the operate-contract's own gate-recording convention across 9 command
files plus a new invariant test that must hold forever; treated as full per the mega-goal's
own framing, not because any single edit is architecturally deep).

## Problem

`RUN_REPORT.md` (`/kit:mega`'s per-sub-goal gate matrix, `commands/mega.md` "Close the run
visibly") can only show a phase as covered if SOME command actually calls `gate-ledger.sh`
for it. A 2026-07-04 audit of every file under `commands/` (re-verified against the current
`master`-based tree on this branch, since sub-goals 03+04 landed after the mega-goal's
original count) found the SAME split the mega-goal's framing named: **11 of 29 commands emit
directly, 18 are dark**, with no distinction anywhere between "this phase genuinely has no
ledger concern" and "nobody wired it yet." RUN_REPORT under-counts silently either way, and a
new command added later with neither an emit nor a documented reason would silently join the
dark 18 with zero test coverage noticing.

Of the 18 dark commands, 9 are **phase-owning** (`spec.md`, `spec-validate.md`, `verify.md`,
`think.md`, `design.md`, `ui-design.md`, `docs.md`, `retro.md`, `explain.md` -- each maps to a
real V-model phase or an established RUN_REPORT-observability phase like `grill`), and 9 are
**utility commands** (`absorb.md`, `adopt.md`, `next.md`, `start.md`, `kit-health.md`,
`draft-agent.md`, `visual-team.md`, `mega.md`, `dispatch.md`) that genuinely have no phase of
their own to record against -- but until now that distinction lived only in a conductor's head,
never in the repo.

## Solution

Two-part close-out, plus the forever-invariant test the mega-goal's over-test framing demands:

1. **Wire the 9 phase-owning dark commands.** Each gains ONE line, at its natural hand-off
   point, in the SAME single-line convention `test-plan.md` / `review.md` / `devs-team.md`
   already use (`bash lib/gate/gate-ledger.sh record <rid> <Phase> ran "<summary>"`):
   - `spec.md` -> `Spec` (a real `Lane x phase depth matrix` row)
   - `spec-validate.md` -> `Validate` (a real matrix row)
   - `think.md` -> `Think` (a real matrix row)
   - `design.md` -> `Design` (a real matrix row, "Design (opt-in)")
   - `ui-design.md` -> `UI design` (a real matrix row, "UI design (opt-in)")
   - `docs.md` -> `Docs` (a real matrix row)
   - `retro.md` -> `Reflect` (a real matrix row -- the command is `/kit:retro` but the phase
     it owns is named `Reflect` in the matrix, so the record call uses that name, not `retro`)
   - `verify.md` -> `verify` (bespoke; `/kit:verify` is on-demand and carries no matrix row of
     its own, same precedent as `grill`'s own non-matrix phase -- pure RUN_REPORT
     observability, never a new required gate)
   - `explain.md` -> `explain` (bespoke, same non-matrix reasoning as `verify`)

   No lane-matrix cell changes: a command that ran unrecorded yesterday becomes VISIBLE today,
   never newly-blocking (`required()`/`check()` are keyed on the SAME matrix rows they already
   were; only 6 of the 9 phases above are matrix rows at all, and none of those 6 gain a new
   `measure-twice` cell -- they already had one, it just had no live emitter).

2. **Document the 9 utility commands as an exemption table**, in `WORKFLOW.md`'s new
   "## Command emit coverage (SPEC-139)" section (single source of truth, parsed by the new
   test, no second copy -- mirrors `matrix_for_lane()`'s own precedent of parsing WORKFLOW.md
   at runtime): `next.md` / `start.md` are read-only detectors that say so in their own text
   ("Do NOT execute anything"); `kit-health.md` / `absorb.md` / `adopt.md` / `draft-agent.md`
   are self-assessment, maintainer-audit, one-time-bootstrap, and meta-generation utilities
   that sit outside any spec's rid/lane lifecycle; `visual-team.md` is a nested critique lens
   invoked FROM `ui-design.md` (whose own new emit now covers that phase); `mega.md` /
   `dispatch.md` already emit, just not as a literal call inside their own prose --
   `mega.md`'s own text says the driver emits `gate-ledger start` per dispatched sub-goal
   (SPEC-101), and `dispatch.md`'s fanned-out workers each run the full `/kit:execute`
   lifecycle (their own gate-ledger calls) inside their isolated worktrees.

3. **A no-orphan sweep test, `tests/test-command-emit-sweep.sh`**, that asserts the invariant
   FOREVER: every command in `commands/` either mentions `gate-ledger` (a real emit) or is
   named in WORKFLOW.md's exemption table. Mirrors the established pattern
   (`tests/test-understanding-wiring.sh` / `tests/test-kri-wiring.sh` /
   `tests/test-docs-wiring.sh`): a generic sweep function, a load-bearing NEGATIVE CONTROL
   (a fixture command with neither an emit nor an exemption entry IS flagged), plus a specific
   proof that the exemption table is load-bearing for `dispatch.md` (which has ZERO
   gate-ledger mentions of its own -- removing its exemption row alone must turn it into the
   ONE new orphan the sweep flags).

**Not changed:** no new gate, no lane-matrix cell, no new required phase. `execute.md`
(`Build`) and the design-record gate are pre-existing gaps (neither is recorded by ANY
command today, `execute.md` narrates escalation/action verbs but never `record`s `build ran`,
and design-record is enforced statically by Reviewer 6 rather than separately recorded) --
both are flagged honestly in WORKFLOW.md's new section as OUT OF SCOPE for this sub-goal
(`execute.md` was already counted among the 11 "emitting" commands in the mega-goal's own
framing, and touching it is not in this sub-goal's named list), with the generic manual-record
escape hatch named for a run that needs either gate satisfied.

## Design

`obvious: not design-bearing`. No new component, no schema change, no external integration, no
irreversible choice: nine markdown edits reusing an established single-line convention, one
new markdown table reusing an established parse-at-runtime pattern, and one new test file
reusing an established no-orphan-sweep shape (three prior siblings in this exact repo). A
diagram would restate the file list above without adding information.

## Acceptance criteria

1. Each of the 9 phase-owning dark commands (`spec.md`, `spec-validate.md`, `verify.md`,
   `think.md`, `design.md`, `ui-design.md`, `docs.md`, `retro.md`, `explain.md`) contains a
   real `bash lib/gate/gate-ledger.sh record <rid> <Phase> ran "..."` call at its natural hand-off
   point, using the phase name given in the Solution section above.
2. `WORKFLOW.md` carries a "## Command emit coverage (SPEC-139)" section naming exactly the 9
   utility commands (`absorb.md`, `adopt.md`, `next.md`, `start.md`, `kit-health.md`,
   `draft-agent.md`, `visual-team.md`, `mega.md`, `dispatch.md`) with a grounded, per-command
   reason, plus an honest note on the pre-existing `Build`/design-record gap (out of scope).
3. `tests/test-command-emit-sweep.sh` passes: every one of the 29 real `commands/*.md` files
   either mentions `gate-ledger` or is named in the exemption table (0 orphans); the exemption
   table names exactly the 9 expected commands, no more no less; each of the 9 newly-wired
   commands is independently verified to carry its specific phase's record call (not just a
   loose pass on AC1's coarser check).
4. NEGATIVE CONTROL (load-bearing): a fixture command with neither a `gate-ledger` mention nor
   an exemption entry IS flagged an orphan by the same sweep function used for AC3, proving the
   sweep catches the bug class, not just that the real repo happens to be clean.
5. A second, narrower negative control proves the exemption table is load-bearing for
   `dispatch.md` specifically (it has zero `gate-ledger` mentions of its own): removing its
   exemption-table row alone makes the sweep flag exactly one new orphan, `dispatch.md`.
6. No regression: the full CI suite (every `bash tests/test-*.sh` referenced in
   `.github/workflows/test.yml`, 33 files after this SPEC adds one) stays green.

## Verification

```
bash tests/test-command-emit-sweep.sh
bash tests/test-understanding-wiring.sh
bash tests/test-kri-wiring.sh
bash tests/test-docs-wiring.sh
bash tests/test-meta.sh
for t in $(grep -oE 'bash tests/test-[a-z0-9-]+\.sh' .github/workflows/test.yml | sort -u | sed 's/bash //'); do bash "$t" >/dev/null 2>&1 && echo "PASS $t" || echo "FAIL $t"; done
```
All green; see `docs/verification/kit-emit-sweep/proof-of-done.md` for the full run-table, the
committed 29-row emit-coverage table, and the live-capture ledger lines.

## Test plan
Date: 2026-07-04
Source: this spec's Acceptance criteria

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | each of the 9 phase-owning commands carries its exact `record <rid> <Phase> ran` call | happy-path | AC1 | 9/9 grep matches, one per command/phase pair | `tests/test-command-emit-sweep.sh` AC3 block |
| 2 | WORKFLOW.md's exemption table names exactly the 9 expected utility commands | happy-path | AC2 | sorted actual list == sorted expected list, no more no less | `tests/test-command-emit-sweep.sh` AC2 block |
| 3 | the full sweep over real `commands/*.md` reports 0 orphans | happy-path | AC3 | sweep_check return code 0, no `ORPHAN:` lines | `tests/test-command-emit-sweep.sh` AC1 block |
| 4 | commands/ has exactly 29 files (pin, catches silent drift) | boundary/edge | AC3 | count == 29 | `tests/test-command-emit-sweep.sh` AC1 block |
| 5 | a fixture command with neither an emit nor an exemption entry | boundary/edge + failure-injection | AC4 | flagged as exactly 1 orphan, named precisely | `tests/test-command-emit-sweep.sh` AC4 block |
| 6 | the two legit fixture copies (an emitter, an exempt) are NOT flagged alongside the bad fixture | regression | AC4 | 0 false positives on the legit copies | `tests/test-command-emit-sweep.sh` AC4 block |
| 7 | removing dispatch.md's exemption row alone (leaving its zero gate-ledger mentions unchanged) | failure-injection | AC5 | sweep flags exactly 1 NEW orphan, `dispatch.md` | `tests/test-command-emit-sweep.sh` AC5 block; also manually demonstrated live (see proof-of-done RED capture) |
| 8 | a fixture description that names "gate-ledger" while explaining it has none (self-referential false-negative trap) | security/abuse | AC4 | the fixture avoids the substring by design; caught once during authoring, fixed | proof-of-done "Grounded negative control" section |
| 9 | full existing CI suite (32 pre-existing files) stays green after all 9 command edits + the WORKFLOW.md table | regression | AC6 | 32/32 PASS, 0 FAIL | Verification section; proof-of-done "Regression" |

### Coverage notes
- Categories skipped: none -- all 5 categories (happy-path, boundary/edge, failure-injection, security/abuse, regression) are represented across cases 1-9 above.
- This is a coverage TARGET across the enumerated categories, not an exhaustive test list.

## Decision Log
- DEC-001: the loose "mentions `gate-ledger`" check (rather than a per-file invocation-shape
  regex) is the sweep's positive-coverage test, because a stricter regex that tries to
  distinguish "a real call" from "a prose mention" turned out to be brittle in practice (the
  first draft's strict `` `bash lib/gate-ledger\.sh <verb>` `` pattern missed `quiz-gate.md`'s
  legitimate `` `gate-ledger.sh debt-response` `` shorthand and would have wrongly flagged it
  an orphan); alternatives rejected: a strict per-file regex (too fragile to phrasing drift), a
  hand-maintained allow/deny list with no grep at all (loses the "did someone actually touch
  the ledger" signal entirely).
- DEC-002: `verify` and `explain` record bespoke, non-matrix phase names (lowercase, no Title
  Case) rather than being shoehorned into an existing matrix row, mirroring `grill`'s own
  established precedent (`lib/gate/gate-ledger.sh`'s `record()` accepts any phase string; only
  `required()`/`plan()`/`progress()` consult the matrix). Alternative rejected: inventing a
  `Verify (opt-in)` / `Explain (opt-in)` matrix row, which the sub-goal's explicit "no
  lane-matrix cell changes" constraint forbids.
- DEC-003: `retro.md` records phase `Reflect` (the matrix's own name for that row), not
  `retro` (the command's own name), because `record()`'s phase argument is what RUN_REPORT and
  `required()`/`check()` key on -- recording `retro` would silently create a SECOND, unmatched
  phase name that never satisfies the real `Reflect` gate. Rejected: recording both `Reflect`
  and `retro` (redundant, and invites drift between the two).
