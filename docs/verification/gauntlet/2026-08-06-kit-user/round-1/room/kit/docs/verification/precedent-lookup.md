# Proof of done: precedent-lookup (SPEC-068)

Behavioral change: lib/precedent.sh added (intake read-back); assign + grill wired.

## Green run

Command: `bash tests/test-hooks.sh`
Exit: 0
Output (tail): `Passed: 307 / 307` , includes the 6 SPEC-068 assertions (matching spec
found + ranked 3x, unrelated spec absent, stopword-only honesty, usage 64, negative
control).

Live smoke on the real repo: `precedent.sh find "tune the lane classifier keywords for
misroutes" 4` returned SPEC-067 / SPEC-062 / SPEC-057 / SPEC-053, all genuinely relevant
prior art for that ask.

## NEGATIVE CONTROL

In-suite, runs every execution: the matching fixture spec file is REMOVED and the
assertion requires it to vanish from the results (`assert_output_not_contains`). A
lookup that hallucinated or cached results would stay GREEN on the first assert and go
RED here.

## Reproduce

```bash
cd dwarves-kit
bash tests/test-hooks.sh   # 307/307
```

VERDICT: PASS
