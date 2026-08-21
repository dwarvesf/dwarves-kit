# Proof of done: gauntlet J3 (full lane) SOLID

Behavioral claim: the kit's process docs steer an unaided probe through the
full lane, repeatably.

## Recorded runs (gate format)

Command: GAUNTLET_RUNNER_HOST=<mini-host> bash tests/gauntlet/cleanroom/run-remote.sh user J3 <round-1 out>  (probe cap 2700s)
Exit: 0
Verdict: PASS

Command: KIT_ROOT=$PWD bash <round-1>/checks/check-submission-user-J3.sh <round-1 fixture>
Exit: 0
Verdict: PASS (SUBMISSION: GREEN, 11/11)

Command: same runner, round 2
Exit: 0
Verdict: PASS

Command: KIT_ROOT=$PWD bash <round-2>/checks/check-submission-user-J3.sh <round-2 fixture>
Exit: 0
Verdict: PASS (SUBMISSION: GREEN, 11/11; two consecutive passes, rule 9)

Command: git -C <fixture> log --all --oneline  (both rounds)
Exit: 0
Verdict: PASS (spec/validate commits precede the feature commit in both histories; ordering is real, not checker-inferred)

Command: grep -c 'sk-ant' <transcript>  (both rounds)
Exit: 1 (no match), both
Verdict: PASS

## Negative control

The J3 checker's failure behavior was proven at build time (SPEC-227 P3
record: bare fixture RED exit 1, BLOCKED shape exit 3) and re-proven in the
doorway proof (removing one artifact flips a GREEN fixture RED). This round
adds the ordering check above as the human-side control on the one property
the checker cannot assert.

Rollback note: additive round records only; revert the commits and nothing
remains to unwind.
