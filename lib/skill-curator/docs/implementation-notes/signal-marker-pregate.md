# Implementation notes: signal-marker pre-gate

Delta log for the opt-in signal-gate (ADR 0010, proof-of-done Feature D). Only what is NOT already
in those two; see them for the decision + acceptance.

## 2026-07-02 10:00 No formal docs/specs/SPEC file for this feature

**Context:** the tool's established pattern is SPEC-103 TASK-NNN per feature. **Decision:** this
feature is specced by ADR 0010 + a proof-of-done Feature D block, no new `docs/specs/SPEC-NNN`.
**Why:** it is a single opt-in gate (one function + one config key + one guard), not a
phase/sub-goal; a full SPEC would out-weigh the change. **Impact:** future features that touch the
reviewer's control flow should still reference ADR 0010, not hunt for a SPEC.

## 2026-07-02 10:05 Marker regex lives inline in reviewer-run.sh, not a lib

**Context:** `has_signal_markers()` could go in `lib/common.sh` next to `contains_secret`.
**Decision:** kept it in `reviewer-run.sh` beside its only caller. **Why:** the gate has exactly one
consumer and the pattern is domain-specific to the reviewer's signal list; co-location beats a
shared-lib indirection. Overridable via `signal_markers` / `CC_SI_SIGNAL_MARKERS` for tuning without
an edit. **Trade-off:** if a second caller ever needs it, promote to `common.sh` then.

## 2026-07-02 10:30 Doc backfill during the SDD review pass

**Context:** README "Knobs", MANUAL config table, and RUNBOOK "cost runs hot" documented every knob
EXCEPT the new gate. **Decision:** added `signal_gate` (+ `signal_markers`) to all three during the
`/kit:docs` step, and named the gate as the first cost lever in the RUNBOOK cost-spike fix. **Why:**
the SDD scope here is end-to-end (docs catch up to code), not code-only.

## 2026-07-02 11:00 Applied 3-lens review findings (kit:review-team, FIX-THEN-SHIP)

Deltas from the review, all folded in before merge:
- **HIGH (test-coverage):** recall was tested against ONE marker category. Expanded `test-signal-gate.sh`
  to assert one representative token PER category (correction/frustration/technique/fix/debug/
  skill-patch) via a `keeps()` helper, so a regex regression on either half of the pattern is caught.
  5 checks -> 12.
- **MED (architecture):** `cc-improve status` counted `skip-no-signal` rows as "reviewer runs",
  hiding real Haiku calls from free skips , exactly the number needed to audit the gate. Split it:
  `reviewer runs` now excludes skips and a `gate-skips (7d)` field appears when >0 (`bin/cc-improve`).
- **MED (test-coverage):** gate-before-lock was only asserted indirectly. Added check [6]: a held
  lock + marker-free run must still emit `skip-no-signal` (a post-lock gate would divert to the
  single-flight path instead), proving the ordering.
- **LOW (security):** `grep -qiE -- "$pat"` so an operator `signal_markers` starting with `-` can't
  be parsed as a flag.
- **LOW (test-coverage):** added check [7], empty-transcript short-circuits before the gate.
- **LOW (architecture):** the skip-path ledger write is the first UNLOCKED writer; recorded in ADR
  0010 trade-offs as accepted (sub-`PIPE_BUF` O_APPEND), not fixed.
