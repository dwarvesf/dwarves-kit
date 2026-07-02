# Implementation notes: lane-machinery coverage (SPEC-098)

Delta from SPEC-098.

## 2026-07-02 the audit's real finding came from the spot-check, not the misfire log

The sub-goal framed this as "audit against recorded misfires". The recorded misfires turned
out clean (0 real faults; 9 identical fixture downgrades). The actual rule-gap surfaced only
by running the OCCURRED task shapes through the live classifier , which the contract permits
("audit against the DATA": the occurred shapes ARE data). Without that second lens the audit
would have wrongly concluded "clean, no change" and missed a real under-gating hole. Noted so
future rule audits do BOTH: disposition the recorded misfires AND spot-check occurred shapes
(the untracked-run gap, ID-085, means the recorded-misfire log alone under-samples reality).

## 2026-07-02 token choice: basenames, not concept words

Added `lane-telemetry|mega-merge|proof-ledger|kit-log-dir` (exact lib basenames), not
generic words like `telemetry` or `ledger`, to avoid escalating unrelated tasks that merely
mention those concepts. Verified precedence (backfill > tiny > hard-gate) still returns tiny
for a cosmetic edit to these libs (AC5), so the addition never over-gates a typo.

## 2026-07-02 no dedicated classifier suite existed

`classify` had only structural pins in test-meta.sh + one assertion in test-lane-escalation.
Created `tests/test-lane-classify.sh` as its first behavioral suite (per the sub-goal's named
proof command `bash tests/test-lane-classify.sh`). Future classifier rule changes pin here.

## 2026-07-02 review pass: completeness sweep + CI wiring + honest limits

Review-team caught that the first pass was self-referential (only the 4 wave-touched libs),
while the SPEC title claimed "all" libs. Response: swept ALL 21 `lib/*.sh`, escalated the
remaining machinery (`orchestrate.sh` anchored to `.sh` since the bare word is common;
`stack-merge`, `role-classify`, `goal-drafts` , siblings of already-covered libs), and
DELIBERATELY held the read-helpers (`precedent`, `route-suggest`, `spec-index`, `spec-next`,
`verif-counts`) at normal, documented. SPEC retitled to match.

CI: `test-lane-classify.sh` (+ the SG-01 `test-ledger-durability.sh`, also unwired) were
missing from `.github/workflows/test.yml` , added, so a future regex edit is caught.

Known limitation (advisor + filed ID-088): the hard-gate matches a MENTION of a basename,
not an edit, so a doc task ABOUT the machinery over-gates to full. Pre-existing; a real fix
needs an edit-vs-mention signal (classifier enhancement, out of this no-rewrite scope).

Discipline note: the published occurred-shape evidence table was re-verified against the
live classifier before ship , 2 of the 6 rows I first drafted were wrong (right-arm-dispatch
and mega-mirror land normal, not full), corrected to the real values + honest "acceptable,
no lib basename named" dispositions. (The advisor's finding-2 was exactly about not
publishing unverified spot-check claims.)
