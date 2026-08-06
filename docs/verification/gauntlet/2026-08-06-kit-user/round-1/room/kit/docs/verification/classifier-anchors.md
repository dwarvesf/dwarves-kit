# Proof of done: classifier-anchors (SPEC-072)

Behavioral change: task-type data-tool anchor narrowed (no bare `cli`); lane tiny
gains doc-bootstrap anchors at a new 3b precedence slot (after hard-gates).

## Green run

Failing-first: the 2 live-misfire pins were RED on the pre-fix tree, GREEN after.

Command: `bash tests/test-hooks.sh`
Exit: 0
Output (tail): `Passed: 359 / 359` (2 failing-first + 4 negatives + 7 review-driven)

Command: `bash tests/test-meta.sh` -> 432/432. `bash tests/test-e2e.sh` -> 20/20
(the golden run itself exercises the demo-CLI phrasing this fix corrects).

## NEGATIVE CONTROL

Measured live, both directions:
- 3b doc-bootstrap block disabled -> 1 RED (ID-064 pin), restored -> green.
- verb arm removed -> first attempt 0 RED exposed the arm as unpinned; a
  verb-arm-only pin was added; removal now -> 1 RED, restored -> green.

## Reproduce

```bash
cd dwarves-kit && bash tests/test-hooks.sh   # 359/359
```

VERDICT: PASS
