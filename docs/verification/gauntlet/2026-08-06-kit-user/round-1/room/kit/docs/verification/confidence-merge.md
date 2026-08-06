# Proof of done: confidence-merge (SPEC-081)

Behavioral change (prose contract): review-team gains the anchored-confidence
merge , 5 anchors with self-tests, fingerprint dedup, one-step corroboration
promotion, LATE <75 gate (CRITICAL at 50+), suppressed appendix, Confidence on
report rows; suppressed findings excluded from routing, verdict, and findings=K.

## Green run

Failing-first: 10 meta pins RED on the pre-edit command -> green.

Command: `bash tests/test-meta.sh`
Exit: 0
Output (tail): `Passed: 465 / 465`

Command: `bash tests/test-hooks.sh` -> 412/412. `bash tests/test-e2e.sh` -> 20/20.

## NEGATIVE CONTROL

Run live at build: the promotion-rule token text-reverted -> 2 RED (promotion pin
+ ordering pin) -> restored green. The ordering pin also carries a uniqueness
guard so anchor-string duplication cannot silently invert it.

## Reproduce

```bash
cd dwarves-kit && bash tests/test-meta.sh
```

VERDICT: PASS
