# Implementation notes: grill-conditioning (SPEC-138)

No deviations from SPEC-138; the delta below is decisions the spec left to implementation, not
disagreements with it.

## 2026-07-04 09:00 Self spec-validate disposition (no fresh dispatch)

Context: `/kit:spec-validate`'s 6 reviewers are prompt text, not code (same honest limitation
`tests/test-design-record.sh` and `tests/test-references-field.sh` already document). This is a
solo autonomous sub-goal (ADR-0032 delegate mode); no adversarial dispatch was run.

Decision: self-checked SPEC-138 against all 6 reviewer lenses inline before flipping Status to
VALIDATED. No CRITICAL/blocking findings; Reviewer 6 (Design Record, the one blocking lens)
passes: the spec is design-bearing (non-obvious control flow: a 3-signal decision tree gates an
existing advisory phase, plus a write-time enum guard in the enforcement layer) and carries a
non-empty `## Design` with a mermaid flowchart + a stated chosen approach.

Why: matches the sibling sub-goals in this same batch (`ug-02-worthiness`, `ug-record-at-ship`),
which self-validated rather than dispatching a second agent for a solo, narrowly-scoped
full-lane change; SPEC-069's multi-lens escalation (this touches `lib/`) is honored at the
Review phase instead (see the 2026-07-04 10:30 entry below), not duplicated at Validate.

Impact: none on shipped behavior; this is a process-disposition note for the ledger.

## 2026-07-04 09:15 Failure-mode addition not in the original research doc

Context: the Failure Mode Analyst self-review lens asked what happens when Step 0's signals
literally cannot be checked (no git binary, `rg` unavailable, a non-git directory). The
research doc (`research/2026-07-04-fable-unknowns-absorption.md` Design 1) does not address this
case.

Decision: added one sentence to `commands/grill.md` Step 0: "If a signal genuinely cannot be
checked ..., treat it as FIRED: fail toward asking, never toward a silent skip."

Why: an advisory precheck that silently fails closed (treats "can't check" as "didn't fire")
would quietly suppress the exact interview the article's whole thesis says to run harder on;
failing open (toward asking) costs at most one extra interview, failing closed costs an unknown
that never surfaces.

Alternatives considered: leaving the case unstated (rejected, an agent under time pressure would
likely guess toward the cheaper AUTO-SKIP path, the wrong direction); treating unchecked signals
as a 4th `reason=` token (rejected, over-engineering a case that should just fire, not skip with
a special label).

Impact: one sentence in `commands/grill.md`; no code change; not in the original spec draft's
first pass, added during the Design write-up and self-validate.

## 2026-07-04 09:30 `operator-wave` absorbs the SPEC-058 carve-out instead of a 4th token

Context: SPEC-058 already has a "conversation already resolved the banks" skip carve-out. A
4-token enum (adding e.g. `reason=pre-resolved`) was considered.

Decision: `operator-wave` covers this case too (recorded as DEC-003 in the spec's Decision Log).

Why: both shapes are "a human, in the moment, decided no interview was needed, overriding what
the mechanical precheck would have said" -- the same thing from the ledger-reader's point of
view. A 3-token enum is simpler for the sibling `ledger-observatory` ceremony-detector (sub-goal
05 downstream) to reason about than a 4th near-duplicate value.

Impact: no code change beyond the 3-token enum already planned; this note exists so a future
reader does not wonder where the SPEC-058 carve-out went.

## 2026-07-04 10:00 Doc-impact: README project structure left untouched (pre-existing gap, not fixed here)

Context: the doc-impact map (`WORKFLOW.md`) names README "Project structure" as a companion for
any `lib/*` change. `lib/gate-ledger.sh` has no dedicated row there today (it is only mentioned
in passing inside `lib/mega-merge.sh`'s row); this predates this change.

Decision: left as-is. `docs/architecture.md`'s existing prose paragraph describing
`gate-ledger.sh` was updated instead (it already itemizes gate-ledger.sh directly).

Why: per the coding-discipline "surgical changes" rule, this session does not retrofit an
unrelated pre-existing documentation gap (adding a README row that never existed) while
implementing a narrow behavioral change; flagging it here rather than silently leaving it.

Impact: none on shipped behavior; a documentation completeness note.

## 2026-07-04 10:30 Review: SPEC-069 multi-lens dispatch (lib/ touched)

Context: this change edits `lib/gate-ledger.sh`, so SPEC-069's escalation rule applies (a run
touching `lib/` or `hooks/` owes multi-lens review, not a single pass).

Decision: dispatched fresh-context `kit:security-reviewer` + `kit:code-reviewer` (architecture
lens) + `kit:code-reviewer` (test-coverage lens) against the diff. Security: SECURE, no
HIGH/MEDIUM findings. Architecture: 9/10, no MEDIUM+ findings. Test-coverage: 6/10, one HIGH +
one MEDIUM finding, both real, both fixed (see the two entries below). See the PR body /
gate-ledger `review` line for the full verdicts.

## 2026-07-04 10:45 Fix: closed-enum bypass via prefix glob (test-coverage review MEDIUM)

Context: the original `record()` guard used `case "$reason" in reason=home-turf*|...`, a
prefix-only glob. The reviewer found live that `reason=home-turfish-nonsense: not a real token`
passed the guard (exit 0, line written), even though SPEC-138 calls the enum "closed."

Decision: tightened the `case` patterns to `reason=home-turf|reason=home-turf:*` (repeated per
token): the reason must be EXACTLY the bare token, or the token immediately followed by `:` (the
documented `reason=<token>: <why>` convention). Added check 5b to
`tests/test-grill-conditioning.sh` asserting the look-alike string is now rejected.

Why: matches the spec's own stated invariant (a genuinely closed enum) rather than a permissive
prefix match; the fix is a 3-line pattern change with no behavior change for any already-valid
caller (grill.md's documented forms all end in `:` or are exact).

Alternatives considered: leaving it as documented behavior (rejected -- contradicts the spec's
explicit "closed enum" language and the security review's own framing of "prefix-match is by
design," which was written before the reviewer's follow-up test-coverage pass caught the actual
bypass); requiring a space after the token instead of `:` (rejected, `:` is what `grill.md`
already documents).

Impact: `lib/gate-ledger.sh`'s case block; `tests/test-grill-conditioning.sh` gained check 5b;
SPEC-138's Technical Design + Test plan + Decision Log (DEC-005) updated to match.

## 2026-07-04 10:50 Fix: TZ- and time-of-day-dependent boundary fixture (test-coverage review HIGH)

Context: `days_ago_iso()` built a calendar-relative timestamp (`date -v-91d +...T12:00:00`, no
`Z`/offset). The reviewer reproduced a live failure under `TZ=UTC` (GitHub Actions' default):
`git commit`'s `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` parse in the LOCAL system timezone
regardless of `-u` generating the string, so the 90-day boundary silently shifted with the host's
UTC offset.

Decision: replaced calendar-day construction with an EXACT epoch offset:
`epoch_days_ago_iso() { target=$(( $(date +%s) - n*86400 )); date -u -r "$target" ... }` (BSD) /
`date -u -d "@$target" ...` (GNU fallback). This is immune to both the TZ bug (the epoch itself
is timezone-free; only the DISPLAY format needs `-u`) and a second, related bug the reviewer's
fix suggestion did not fully cover: a fixed "noon" commit time is still time-of-day-dependent
(the day-count boundary rounds differently depending on what time the suite happens to run,
relative to noon). Exact epoch arithmetic removes both failure modes at once.

Why: proven by re-running `tests/test-grill-conditioning.sh` under `TZ=UTC` and
`TZ=America/Los_Angeles` in addition to the host's local TZ (ICT) -- all three show 23/23,
including both the 89d-fresh and 91d-stale boundary checks.

Alternatives considered: just appending `Z` to the existing noon-based string (the reviewer's
literal suggestion; rejected as incomplete, since it fixes the TZ bug but leaves the
time-of-day-rounding bug); moving the fixture days further from the edge (e.g. 60d/120d,
also suggested; rejected, it would stop testing the actual 90-day boundary the over-test asks
for).

Impact: `tests/test-grill-conditioning.sh`'s `days_ago_iso` renamed to `epoch_days_ago_iso` and
rewritten; `commit_dated`'s call site updated; SPEC-138's Decision Log (DEC-006) updated.
