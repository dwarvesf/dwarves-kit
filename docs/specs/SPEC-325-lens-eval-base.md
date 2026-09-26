# SPEC-325: lens-eval names the base a `fewer` signal assumes

**Status:** DRAFT
Lane: full
Type: spec-feature
**Proof:** `docs/verification/lens-eval-base.md`; `tests/test-lens-eval.sh`.

## Problem

`lib/bench/lens-eval.sh` scores a `control: fewer` signal by comparing hit counts: it passes
when treatment hits and control hits fewer times. That comparison only means something when
`<base-ref>` predates the lens capability the signal names, so the control arm can plausibly
lack it. `docs/verification/r7-quiet-calibration.md` hit this by construction: the run used
`origin/master` as base, but master already carried the SPEC-314 sustainability lens (the fix
under test only touched one wording branch inside it). Control and treatment then tied on
`liveness-any`, `retirement-any`, and `rotation-any` (3/3 both arms), and all three FAILed, not
because the fix regressed anything, but because the chosen base already had the capability those
signals expect it to lack. The verification doc's own "Limits" section had to explain this by
hand, after the fact, per FAIL.

Nothing in the script or the README says a `fewer` signal carries this assumption, and nothing
flags the case when it breaks. The next lens change against a too-recent base repeats the same
manual limits paragraph.

## Contract

- `lib/bench/README.md`'s "lens-eval" section gains a rule, next to the existing `fewer`/`miss`
  table: a `control: fewer` signal is only meaningful evidence when `<base-ref>` predates the
  capability the signal names. Run against a base that already carries it, and control ties or
  beats treatment, so the signal fails by construction, not from a regression. Pick a base
  before the lens landed, or drop the `fewer` signal for that base and keep the hard `hit`/`miss`
  signals, which do not carry this assumption. The rule cites the r7-quiet-calibration run as the
  worked example: three `-any` signals FAILed against `origin/master` for exactly this reason.
- `lens-eval.sh`'s scoring loop counts, across all signals in the run, how many carry a `fewer`
  expectation and how many of those show no gap (control hit count is not strictly fewer than
  treatment's). When every `fewer` signal in the run shows no gap (and at least one such signal
  ran), the script prints one extra line after the table, before the summary:
  `note: all <n> 'fewer' signals show no gap between arms; base <base-ref> may already carry
  what they assume it predates`.
- The note is silent when zero signals carry `fewer`, or when at least one `fewer` signal still
  shows a gap (a real per-signal regression looks different from every gap collapsing at once,
  so the note stays a diagnostic, not a replacement for reading the per-signal FAIL rows).
- No new flag, no case-file field, no new exit code. The verdict and exit status (0/1/2/3/64)
  are unchanged; a run that FAILs on `fewer` signals still FAILs, now with one more line
  explaining a likely cause.

## Picture

```
 scoring loop, per signal
     |
     v
 want = fewer? --no--> score as today
     |
    yes
     v
 fewer_total++          h < ht? --yes--> fewer_nogap unchanged, PASS
     |                      |
     v                     no
 fewer_nogap++ <-----------+                                   FAIL (unchanged)
     |
     v
 after the table, before summary:
 fewer_total > 0 and fewer_nogap == fewer_total?
     |
    yes --> print the note line
     |
     no --> silent
```

## Design

obvious: a doc rule plus one counter-driven warning line, read off comparisons the scoring loop
already makes. No new flag, schema field, control-flow branch, or exit code; the fix is legibility,
not a new mechanism.

Approaches considered:

| Approach | Why not |
|---|---|
| A case-file field naming the base a signal assumes (e.g. `assumes_base_before`) | Needs a schema addition, a jq check, and a way to compare it against the actual `<base-ref>` argument (a ref, not a date or capability marker) with no cheap way to verify "predates the lens" from a ref name alone. The counter-based note is derived from data the script already computes, at zero schema cost. |
| Fail the run (new exit code) when the note condition holds | The condition is a heuristic (all gaps collapsing looks like a bad base, but could rarely be a real total regression); a hint should not change the pass/fail contract callers already parse. |
| Warn per-signal, inline in the table row | The signal-file table already prints the counts; a per-row explanation of "why fewer failed" would repeat the same sentence once per signal in the common case (a bad base fails all of them together). One note after the table says it once. |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: the rule | `lib/bench/README.md` | the Contract's README rule, with the r7-quiet-calibration example |
| T2: the warning | `lib/bench/lens-eval.sh` | the Contract's counter and note line |
| T3: tests | `tests/test-lens-eval.sh` | note fires when all `fewer` signals show no gap; silent when one still shows a gap; silent with zero `fewer` signals; note text names the base ref and the count |
| T4: docs | `docs/CHANGELOG.md`, regenerated `docs/FEATURES.md` | the new note behavior is listed |

## Test plan

| Case | Setup | Expected |
|---|---|---|
| All fewer, no gap | two `fewer` signals, both control ties treatment | the note line prints, naming `2` and the base ref |
| One still shows a gap | two `fewer` signals, one ties, one control strictly fewer | no note line |
| No fewer signals | a case file with only `hit`/`miss` signals | no note line |
| Single fewer, no gap | one `fewer` signal, control ties treatment | the note line prints, naming `1` |
| Exit status unchanged | any of the above | exit code matches what today's script would return (0/1/2/3/64), the note never changes it |

Negative control: `lib/gate/negctl.sh` deletes the `fewer_nogap == fewer_total` check (or the
counter increments). The "All fewer, no gap" and "Single fewer, no gap" rows must go red (no
note line printed where one is expected).

## Verification

`bash tests/test-lens-eval.sh` exits 0. `bash tests/run-all.sh --changed` exits 0.
`lib/gate/negctl.sh` reports the suite red under the mutation above.

## After state

A `lens-eval.sh` run against a base that already carries the capability its `fewer` signals
probe prints one extra line saying so, next to the FAIL rows it would already show. Reading the
"Limits" section by hand, as `docs/verification/r7-quiet-calibration.md` did, is no longer the
only way to notice this. Not covered: the script still cannot choose a better base for the
operator, or verify from a ref alone whether it predates a given lens; the note is a hint to
re-read the base choice, not a fix for picking one.

## Decision Log

- Chose a runtime warning over a case-file field: cheaper, derived from counts the script
  already has, and does not ask case authors to state something (a ref predating a capability)
  the script cannot itself verify.
- The note requires ALL `fewer` signals in the run to show no gap, not just one, so a genuine
  partial regression (some signals still show a gap, one does not) keeps reading as a plain FAIL
  rather than being explained away by the note.
- No new exit code: the note is a hint alongside the existing FAIL, never a reason to change
  what counts as pass or fail.
