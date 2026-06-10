# SPEC-053: Lane-classification floor check (advisory)

Status: SHIPPED ([Unreleased]; revived 2026-06-10: the original 2026-05-23 PR #13 went stale when #26 rewrote the classifier to flag-scoring; the floor check was re-ported onto classify_core, behavior unchanged)
Lane: normal
Backlog: ID-043
Branch: feat/lane-floor-check

## Problem

The classify-then-route audit (this session) confirmed the kit can take a task,
classify it onto a lane, and route it. But it flagged one residual gap: the
classification is **advisory with no floor**. `lib/lane-classify.sh classify`
turns task text into a suggested lane deterministically, yet nothing compares the
lane a human or the LLM actually **chooses** in `/kit:assign` against that
suggestion. So an under-sized lane slips through silently: a task whose text hits
the `full` triggers (auth, hooks, data model, migration, secrets, an external
provider/API contract, payments, validation) can be driven down the `normal` or
even `tiny` lane, skipping the ceremony those triggers exist to force, and the kit
never says a word.

Concretely today: `lane-classify.sh classify "add a hook that touches auth token
validation"` prints `full`, but if the BACKLOG row or the operator says `normal`,
`/kit:assign` proceeds with no warning. The dangerous direction (under-sizing) is
exactly the one with no guard.

## Solution

### Approaches considered

- **A. Floor-check subcommand on the existing classifier (chosen).** Add
  `lane-classify.sh check <chosen-lane> "<desc>"`: it runs the existing
  `classify_core` on the description, compares the chosen lane's risk rank against
  the suggestion's, and WARNs + logs when chosen is lighter than the floor. Reuses
  the one encoded copy of the WORKFLOW triggers. No new file.
- **B. New `lib/lane-floor.sh` file.** Rejected: premature abstraction (the kit's
  3x rule). The logic is one comparison built directly on `classify_core`; a second
  file would duplicate the classifier's wiring and split one concern across two
  files.
- **C. A PreToolUse/Stop hook that enforces lane sizing.** Rejected: there is no
  Claude Code event that carries "a lane was chosen", so a hook cannot see it; and
  hard-gating process-classification inverts "Detect, don't dictate" (PHILOSOPHY)
  and pre-empts ID-036's hooks-as-fallback layering decision.

### Chosen approach + why

Approach A. The floor-check is a thin, deterministic comparison that belongs in the
same domain (and same file) as the classifier it builds on. It SUGGESTS, never
blocks, matching the kit's classifier contract ("Detect, don't dictate"). It is
wired at the one place a lane is committed: `commands/assign.md` Step 5.

### Extensibility & boundaries

- Load-bearing dimension: the lane risk-rank order. If a new lane is added to
  WORKFLOW, add it to the rank map in one place (`lane_rank`) beside the existing
  `classify_core` precedence. The rank order is the only new knowledge.
- Unit boundary: `check` is a pure function of (chosen lane, description) -> a
  warn-or-silent decision + a log line. Testable in isolation with no filesystem
  state beyond the (overridable) log dir.

### Architecture

```
/kit:assign Step 5 picks a lane (BACKLOG column, or override, or lane-classify suggestion)
        │  chosen-lane, task description
        ▼
lane-classify.sh check <chosen> "<desc>"
        │  suggested = lane_classify("<desc>")        (reuses the encoded triggers)
        │  rank(chosen) < rank(suggested) ?
        ├─ yes → stderr WARN "LANE-DOWNGRADE ..." + append to completeness.log ; exit 0
        └─ no  → silent ; exit 0                       (never blocks)
```

## Technical Design

### Interfaces (I/O contract)

- Inputs / consumes: `check <chosen-lane> "<description>"`. `<chosen-lane>` is one
  of the five lane names; `<description>` is the same one-line task text
  `classify` accepts.
- Outputs / produces: on a downgrade, one `LANE-DOWNGRADE: chosen=<x>
  suggested=<y> | <desc, truncated>` line on **stderr**, and one appended line in
  `$DWARVES_KIT_LOG_DIR/completeness.log` (default `~/.claude/dwarves-kit/logs/`)
  in the existing `<iso8601> | LANE-CHECK | ...` shape. On no downgrade: no output.
  Exit code is **always 0** (advisory).
- Invariants: `check` never exits non-zero and never blocks; it reuses
  `classify_core` (one copy of the triggers); an unknown `<chosen-lane>` is itself
  a warned condition, not a crash.

### Risk-rank order

`tiny=1 < normal=2 = bug=2 = backfill=2 < full=3`. A downgrade fires only when
`rank(chosen) < rank(suggested)`. This makes the headline case (`full` floor vs a
lighter chosen lane) loud, catches `tiny` chosen when the text is not cosmetic, and
stays silent on same-rank or heavier choices (over-sizing is always safe per
WORKFLOW "when in doubt, heavier").

### Data model changes
None.

### API changes
One new subcommand on `lib/lane-classify.sh` (`check`); `classify` and `lanes`
unchanged. The usage string and the dispatch `case` gain one arm.

### UI changes
None (CLI helper).

### Infrastructure changes
None.

## Task Breakdown

### Phase 1: Core
- [ ] TASK-001: Add `lane_rank` + `lane_check` to `lib/lane-classify.sh` and a `check` arm to `main`., `check` warns on a downgrade (stderr `LANE-DOWNGRADE`), is silent otherwise, always exits 0, and appends a `LANE-CHECK` line to `$DWARVES_KIT_LOG_DIR/completeness.log` only on a downgrade.
- [ ] TASK-002: Wire the floor-check into `commands/assign.md` Step 5, after the lane is chosen (column or override or suggestion)., Step 5 instructs running `bash lib/lane-classify.sh check <chosen> "<title>"` and surfacing any `LANE-DOWNGRADE` to the operator before hand-off; framed as advisory.

### Phase 2: Verify + document
- [ ] TASK-003: Add a `lane-classify: floor check` block to `tests/test-hooks.sh`., Covers: `full` suggested + `normal` chosen → warns; `full` chosen + `full` suggested → silent; `tiny` chosen + `normal`-suggested text → warns; heavier-than-floor (`full` chosen, `normal` text) → silent; exit code always 0.
- [ ] TASK-004: Sync docs, WORKFLOW.md (note the advisory floor-check beside the classifier / in the alternate-flows completeness note) and MANUAL.md (`/kit:assign` entry)., A reader learns the floor-check exists, is advisory, and where it fires.
- [ ] TASK-005 (lead, at convergence): add a `tests/test-meta.sh` guard asserting `lane-classify.sh` exposes a `check` subcommand and `commands/assign.md` references it., Hands-off for the worker.

## After state

- [ ] `bash lib/lane-classify.sh check normal "add a hook that touches auth token validation"` prints a `LANE-DOWNGRADE` warning to stderr and exits 0. (Today: no such subcommand; the mismatch is invisible.)
- [ ] `bash lib/lane-classify.sh check full "add a hook that touches auth token validation"` prints nothing and exits 0.
- [ ] On a downgrade, a `| LANE-CHECK |` line is appended to `completeness.log`; on a match, nothing is appended.
- [ ] `commands/assign.md` Step 5 instructs running the floor-check after choosing the lane.
- [ ] WORKFLOW.md and MANUAL.md mention the advisory floor-check.
- [ ] `bash tests/test-hooks.sh && bash tests/test-meta.sh` exit 0.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover happy path (downgrade warns) + edge cases (match silent, heavier silent, unknown lane, always-exit-0)
- [ ] No regressions: `classify` and `lanes` behavior unchanged

## Verification
`bash tests/test-hooks.sh && bash tests/test-meta.sh`

## Edge Cases
1. Chosen lane equals the suggested lane → silent, exit 0.
2. Chosen lane is heavier than suggested (e.g. `full` chosen, cosmetic text) → silent, exit 0 (over-sizing is safe).
3. Unknown `<chosen-lane>` string → warn that the lane is unrecognized, exit 0 (do not crash, do not block).
4. Empty description → treated as `normal` by `classify_core`; `check` against it behaves per rank, exit 0.
5. `backfill` suggested vs a non-backfill chosen → same-rank (2) unless chosen is `tiny`; only `tiny` warns. No false positive on normal/bug.

## Out of Scope
- Wiring the floor-check into `/kit:dispatch` (it seeds lanes from the classifier directly, so it cannot downgrade).
- Any hard block or hook (ID-036 owns the hooks-as-fallback layer).
- Changing the existing trigger keywords in `classify_core`.

## Touches
- lib/**
- commands/**

(`tests/test-meta.sh`, `CHANGELOG.md`, `VERSION`, `_meta/BACKLOG.md`, and the version-surface files are lead-owned hands-off shared surfaces per WORKFLOW.md; the lead writes them at convergence.)

## Decision Log
- DEC-001: Subcommand on `lane-classify.sh`, not a new file. Rationale: builds on `classify_core`; a new file is premature abstraction (3x rule). Rejected: `lib/lane-floor.sh`.
- DEC-002: Advisory (warn + log, always exit 0), never a block. Rationale: "Detect, don't dictate"; the classifier's own contract. Rejected: a hard gate / a hook.
- DEC-003: Risk-rank `tiny<normal=bug=backfill<full`, warn only on `rank(chosen)<rank(suggested)`. Rationale: makes the `full`-floor case loud and the under-sized-`tiny` case visible, with near-zero false positives; over-sizing stays silent (always safe).
- DEC-004: Wire at `commands/assign.md` Step 5 only. Rationale: the single place a lane is committed by a human/LLM; `/kit:dispatch` auto-seeds from the classifier and cannot downgrade.

## Review

### Verdict: SHIP

### Findings
- **Security (PASS).** The helper writes only a truncated (<=100 char, newline-stripped) task title to a namespaced log under `DWARVES_KIT_LOG_DIR`; `printf` uses a fixed format string with the data as args (no format-string injection); exit is always 0 so it cannot be abused to block or DoS the intake. No secrets or paths logged.
- **Architecture (PASS).** One comparison built on the existing `classify_core` (no new file, 3x rule honored); wired at the single point a lane is committed (`/kit:assign` Step 5); advisory-only, consistent with "Detect, don't dictate" and the classifier's own contract. `/kit:dispatch` correctly excluded (it seeds from the classifier, cannot downgrade).
- **Test coverage (PASS).** 7 behavior tests (downgrade warns, match silent, tiny under-size warns, over-size silent, unknown lane, always-exit-0, completeness.log written) + 2 meta guards (subcommand exists, assign.md wired). All spec edge cases covered. `classify`/`lanes` regression-checked.
- **LOW (no action).** Rank ties `normal=bug=backfill=2`, so a bug mis-sized as normal does not warn. Intentional (DEC-003): same ceremony weight, near-zero false positives. Documented.

### TODOs
(none)

## Open questions
(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
