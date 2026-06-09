# Verification: ship-gate fail-closed (SPEC-048)

Proof class: behavioral (changes how the ship-gate gates a push). Reproduce:
`bash tests/test-ship-gate-fail-closed.sh` (5/5) + the live run below. Last run: 2026-06-09.

## GREEN: the block (adopted repo + spec + no Lane header)

```
# temp repo: docs/verification/README.md (marker) + docs/specs/SPEC-001-demo.md WITHOUT a Lane:
$ printf '{"tool_input":{"command":"git push -u origin HEAD"}}' | bash hooks/ship-gate.sh
BLOCKED: ship-gate. Spec 'demo' has no 'Lane:' header, so its required gates cannot be checked.
Add a lane to .../SPEC-001-demo.md (e.g. 'Lane: full'). Classify with:
  bash ".../lib/lane-classify.sh" classify "<task>"
$ echo $?
2
```

A spec-driven change in an adopted repo can no longer ship lane-less. This is the half of the
growatt-tui gap that belongs to the gate (the other half, no per-repo contract, is `/kit:adopt`).

## NEGATIVE CONTROL: declare a lane -> passes

```
# same repo, now SPEC-001-demo.md has `Lane: tiny`, and the tiny-lane gates are recorded
$ printf '{"tool_input":{"command":"git push -u origin HEAD"}}' | bash hooks/ship-gate.sh
$ echo $?
0
```

The block is falsifiable: declaring a lane (and recording its gates) flips exit 2 -> exit 0. A
change that made the gate always-block would fail this control.

## Fail-open preserved (the gate never blocks unrelated work)

`tests/test-ship-gate-fail-closed.sh` covers three fail-open cases, all exit 0: no proof marker
(non-adopted repo), no spec for the slug, and a non-`git push` command. Plus the lane+gates pass
case. 5/5.

## Suite

`bash tests/test-ship-gate-fail-closed.sh` -> PASS=5 FAIL=0. `bash tests/test-meta.sh` -> 392/392.

## Verdict: PASS
