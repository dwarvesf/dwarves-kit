# Proof of done: review-routing-tiering (SPEC-078)

Behavioral change (prose contract + pins): review-team gains apply-class routing
(Route per finding, 3 classes, conservative rule, per-class destinations at the
decision gate) and model tiering (explicit session-model override for the
security lens, mid-tier for the rest).

## Green run

Failing-first: the 5 SPEC-078 meta pins were written and run against the
pre-edit command -> 5 RED; edits applied -> green.

Command: `bash tests/test-meta.sh`
Exit: 0
Output (tail): `Passed: 449 / 449`

Command: `bash tests/test-hooks.sh` -> `Passed: 398 / 398`. `bash tests/test-e2e.sh` -> 20/20.

## NEGATIVE CONTROL

Run live at build: the `gated_auto` token text-reverted across the command ->
1 meta pin RED -> restored -> green. (The pins grep the live command text, so a
prose regression flips them; reverting either absorbed block reproduces RED.)

## Reproduce

```bash
cd dwarves-kit && bash tests/test-meta.sh   # 449/449
```

VERDICT: PASS
