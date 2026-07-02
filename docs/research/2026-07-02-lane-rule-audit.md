# Lane-classify rule-correctness audit (SPEC-098, kit-telemetry SG-03)

Date: 2026-07-02
Board: ops-toolkit ID-149 (narrowed remainder: the lane-classify RULE audit; the
verifier-coverage + under-gating halves shipped in kit-hardening SG-04/05/06)
Method: audit the task-shape -> lane rules in `lib/lane-classify.sh` against RECORDED
reality (the ledger misfire corpus) + a rule-correctness spot-check on the task shapes
that actually occurred in the kit-hardening + kit-telemetry waves.

## Part 1: recorded-misfire disposition

Capture (`bash lib/lane-telemetry.sh misfires`, floor-check section):

| Misfire signature | Count | Distinct? | Disposition |
|---|---|---|---|
| `chosen=tiny suggested=full \| add user authentication with jwt sessions` | 9 | **No** , byte-identical text, only the timestamp differs | **operator-error / test-fixture noise, NOT a rule fault.** The string is a canonical TEST fixture (test-lane-escalation / test-hooks / the escalation examples); those `check` calls reached the real `completeness.log` because some ran without `DWARVES_KIT_LOG_DIR` set. Already filed as **ID-087** (SG-02 bonus). No rule change. |
| lane-misrouted (chosen != classified) among tracked runs | 0 | , | `lane-telemetry.sh report` headline `lane-misrouted: 0`, BUT this is **NULL (not measurable)**, not a clean bill: SG-02's eval (`docs/research/2026-07-02-effectiveness-eval.md`, metric 1) verdicted this exact figure NULL because only 1/10 runs is START-tracked (the untracked-run gap, ID-085). "0 misroutes" here means "0 among 1 measurable run", not "the rules are proven right". This is precisely why Part 2's occurred-shape spot-check is needed. |

Key point: the one repeated signature is the classifier working **correctly** , "add user
authentication" hits the `auth` hard-gate -> `suggested=full`, and the floor-check rightly
WARNED that a `tiny` choice was under-sized. The rule is right; the noise is a test writing
to the real log. So the recorded-misfire corpus yields **zero confirmed rule faults**.

## Part 2: rule-correctness spot-check (occurred shapes)

A clean recorded-misfire corpus does not mean the rules are correct , the untracked-run
gap (SG-02 metric 3, ID-085) means most runs never recorded a chosen-vs-classified pair to
misfire in the first place. So I ran the ACTUAL occurred task shapes (the 8 kit-harden +
5 kit-telem sub-goals) through the live classifier and checked each landed in the right lane.

**Confirmed rule-gap (CONFIRMED, fixed):** the `kit-machinery` hard-gate regex covers
`gate-ledger / ship-gate / lane-classify / proof-gate / task-type-classify / goal-registry /
dispatch-gate / backlog.sh / install.sh / adopt.sh / workflow.md` but MISSED four libs that
are equally enforcement/telemetry machinery:

| Machinery lib (occurred / class) | Before | After fix |
|---|---|---|
| `lib/lane-telemetry.sh` (SG-04; eval data source) | normal | **full** |
| `lib/mega-merge.sh` (SG-05; auto-merge enforcement) | normal | **full** |
| `lib/proof-ledger.sh` (SG-01; proof-of-done gate) | normal | **full** |
| `lib/kit-log-dir.sh` (SG-01; durable-storage substrate) | normal | **full** |
| `lib/orchestrate.sh` (review pass; the orchestration driver, 457 LOC, most-active) | normal | **full** |
| `lib/stack-merge.sh` (review pass; mega-merge's PR-merge sibling) | normal | **full** |
| `lib/role-classify.sh` (review pass; sibling of covered task-type-classify) | normal | **full** |
| `lib/goal-drafts.sh` (review pass; sibling of covered goal-registry) | normal | **full** |
| (control) `lib/gate-ledger.sh` | full | full |

Disposition: **rule-gap**. The first four surfaced from this wave's own occurred shapes;
the next four from a review-driven completeness sweep of ALL 21 `lib/*.sh` (the first pass
was self-referential to the 5 wave sub-goals, an honest gap the review caught). All eight
are enforcement / orchestration / telemetry surfaces; work on them should size `full` like
`gate-ledger`. **Fix:** add the basenames to the hard-gate regex (SPEC-098), `orchestrate`
anchored to `\.sh` (common word). The remaining read/helper libs (`precedent`,
`route-suggest`, `spec-index`, `spec-next`, `verif-counts`) are DELIBERATELY held at
`normal` (read-back / navigation / counting, not enforcement).

### Occurred-shape spot-check evidence (the OTHER shapes, not just the gaps)

To back the "checked each occurred shape" claim (advisory: it must be falsifiable), the
non-gap kit-hardening + kit-telemetry sub-goal shapes were also run through the live
classifier; all landed correctly:

| Occurred shape (as phrased) | Lane | Disposition (verified live) |
|---|---|---|
| `every-step review escalation for lib/hooks changes` (kh SG-05) | full | correct (hook hard-gate) |
| `deployable-done UAT gate on the ship-gate` (kh SG-07) | full | correct (ship-gate) |
| `rename the advisor agent and fix naming` (kh SG-02) | tiny | correct (cosmetic; precedence beats hard-gate) |
| `right-arm parity: wire per-phase verifiers into dispatch` (kh SG-04) | normal | ACCEPTABLE , the phrasing names no covered lib basename ("dispatch" != "dispatch-gate"); the actual lib/ touch is backstopped by SPEC-069 review-team + the SPEC-094 spec->build escalation, not the classify-time text. Not escalated here on purpose (no speculative bare-"dispatch" rule). |
| `mega-mirror reconcile in commands/mega.md` (kh SG-08) | normal | ACCEPTABLE , a `commands/*.md` change, not a lib; the hard-gate keys on lib/enforcement surfaces, and `mega.md` names no covered basename. |
| `execute the SPEC-073 effectiveness eval` (kt SG-02) | normal | ACCEPTABLE , an eval task; it escalates to full only once its description names a machinery lib (which the real SG-02 did via lane-telemetry). |

Honest note: two of these land `normal` because the classifier keys on NAMED lib/enforcement
surfaces, not on conceptual machinery-adjacency. That is by design (avoids over-gating every
task that says "dispatch" or "mega"); the lib/ review-team escalation (SPEC-069) and the
spec->build re-classification (SPEC-094) are the backstops for work whose one-line text
under-names its surface. This is the same untracked/under-named-surface theme as ID-085.

Pinned in `tests/test-lane-classify.sh` (AC1-AC6, 16 pins): all eight escalate to full; the
over-match + read-helper negative controls stay normal; a cosmetic edit stays tiny;
previously-covered machinery + a plain feature are unchanged.

### Known limitation (mention vs edit, pre-existing)

The hard-gate matches a textual MENTION of a lib basename, not a diff that touches the file.
So a doc/research task ABOUT this machinery (e.g. "explain mega-merge.sh in the architecture
doc") over-classifies to `full`. This predates SPEC-098 (`gate-ledger` already behaves this
way) and fixing it needs an edit-vs-mention signal the classifier lacks (a rewrite, out of
scope). Widening the token set widens this surface , note that THIS sub-goal's own
description, which names all eight libs, would itself over-gate. Filed as a follow-up board
row (ID-088) rather than fixed here.

## Rules deliberately NOT changed (audited, held)

- `auth` -> full: works (the 9 downgrades prove it fires correctly, AND the occurred-shape
  spot-check confirms it). No change.
- tiny / backfill precedence: confirmed by the STRONGER method too , the occurred `rename
  the advisor agent` shape lands `tiny`, and the AC5 negative control (`fix a typo in
  lib/mega-merge.sh` -> tiny) proves precedence beats the widened hard-gate. Held, evidenced.
- soft-flag counting (2-3 -> normal, 4+ -> full): held, but on the WEAKER evidence , no
  recorded misfire AND no occurred shape tripped it, but the spot-check was hard-gate-focused,
  not a systematic soft-count audit across all 13 shapes. **Honest limit (advisory):** this
  hold rests partly on the Part-1 method that Part-2 proved can be blind; a systematic
  soft-count spot-check is deferred (no observed failure motivates it now , YAGNI , but it is
  not as strongly evidenced as the hard-gate lens). Noted, not hidden.
- No new lanes, no classifier rewrite.

## Outcome

Not a purely clean audit: the recorded-misfire corpus was clean (0 real faults, evidenced
by the fixture-only downgrade capture), but the occurred-shape spot-check found ONE real
rule-gap (kit-machinery under-coverage of four enforcement libs), now fixed + pinned. The
cross-repo ops row **ID-149** flips at the mega-goal close (noted in NOTES).
