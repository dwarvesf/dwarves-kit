# Verification: negctl bounded retries for a probabilistic test

`lib/gate/negctl.sh` ran the RED step exactly once and treated `run_test` as deterministic. A flaky suite could therefore come back green under a REAL mutation, and negctl recorded `test stayed green under the mutation (the check is vacuous)`. The mutation was real; the verdict said otherwise.

This is not hypothetical. On 2026-09-11 a wavefront negative control passed at 1-minute load 11.4 and looked like it refuted a correct fix. Re-run under matched load it failed 3 of 3. The control was probabilistic and the tool had no way to say so.

## Change

`NEGCTL_RED_ATTEMPTS=<n>` (default 1) retries ONLY the RED step and takes the first non-zero exit as RED.

Three properties hold it to the same standard as before:

- **It cannot manufacture red.** A genuinely vacuous mutation stays green on every attempt and still FAILs. Pinned at 5 attempts by case [13].
- **The default path is byte-identical**, including the single-attempt wording. Two dated proof records (`docs/verification/docs-scattered-ids.md`, `docs/verification/command-autonomy-knobs.md`) quote that line verbatim, so it is load-bearing text and is left alone.
- **A bad value is rejected, never coerced.** Non-numeric and zero both exit 64 naming the variable. Silently becoming 1 would read as a clean single-attempt run and hide that the operator asked for more.

Load is deliberately NOT an option here. Holding machine load from a proof tool is hostile on a shared box, so that half stays in `docs/verification/wavefront-startup-windows-negctl.sh`, which induces load around negctl rather than inside it.

## Green run

```
Command: bash tests/test-proof-negctl.sh
[11] a flaky test defeats the single-attempt control (documents the gap)
  ok: one attempt calls a real mutation vacuous, and the default wording is unchanged
[12] NEGCTL_RED_ATTEMPTS=3 catches the same real mutation
  ok: retry reaches RED and names which attempt bit
[13] retries never manufacture RED: a vacuous mutation stays FAIL at 5 attempts
  ok: a genuinely vacuous mutation is still rejected
[14] the default run is byte-identical: no attempt wording at all
  ok: unset NEGCTL_RED_ATTEMPTS prints the original lines
[15] a non-numeric or zero NEGCTL_RED_ATTEMPTS is REJECTED, never coerced to 1
  ok: both bad values exit 64 naming the variable
test-proof-negctl: all 16 passed
Exit: 0
Verdict: PASS
```

The fixture is deterministic, not actually flaky: under mutation it is green on the first red-step run and red from the second, which is a flake's shape without the coin flip. Its counter lives OUTSIDE the repo, because negctl treats an untracked leftover as a FAIL and a counter file inside the tree would trip that check rather than the one under test.

## Negative control

Revert ONLY the implementation and keep the new cases, so the cases prove they bite.

```
Command: git checkout HEAD~1 -- lib/gate/negctl.sh && bash tests/test-proof-negctl.sh; git checkout HEAD -- lib/gate/negctl.sh
grep -c NEGCTL_RED_ATTEMPTS lib/gate/negctl.sh  ->  0
[12] NEGCTL_RED_ATTEMPTS=3 catches the same real mutation
  FAIL: rc=1
[13] retries never manufacture RED: a vacuous mutation stays FAIL at 5 attempts
  FAIL: rc=1
[15] a non-numeric or zero NEGCTL_RED_ATTEMPTS is REJECTED, never coerced to 1
  FAIL: rc=0 rc0=0
test-proof-negctl: 13 passed, 3 FAILED
restored: 0 dirty
Verdict: RED as expected, then restored clean
```

Exactly the three cases that assert the new behaviour fail. Cases [11] and [14] pass against BOTH implementations, which is what proves the default path is unchanged rather than merely asserted to be.

## Reproduce

```bash
bash tests/test-proof-negctl.sh
NEGCTL_RED_ATTEMPTS=5 bash lib/gate/negctl.sh <root> "<test-cmd>" "<mutate-cmd>"
```

## Scope

`docs/FEATURES.md` stays fresh: the cases were added to an existing suite rather than a new test file, so SPEC-219's freshness pin is untouched. `lib/gate/proof-ledger.sh`'s `negctl` verb forwards to this script and needed no change; case [2] still covers it.
