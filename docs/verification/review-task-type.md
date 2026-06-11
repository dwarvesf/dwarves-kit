# Proof of done: review-task-type (SPEC-079)

Behavioral change: 12th task type `review` across every parity surface
(classifier 6b + negative guard, registry, loops row, 5b dialect, grill bank,
type lists, counts).

## Green run

Failing-first: 4 RED on the pre-rule tree -> green. Review fixes (types-12 pin,
guard pins) -> 408/408 hooks, 449/449 meta, 20/20 e2e.

Live: `task-type-classify classify "review this PR adversarially"` -> review;
`proof-gate contract` -> class=inert via the SPEC-071 registry floor.

## NEGATIVE CONTROL

Run live at build: the 6b rule echo disabled -> 4 RED -> restored green. The
review also proved the OLD meta pins were unfalsifiable at 12 (hardcoded
alternation passed with the row deleted); the pins now count 12 and include
review in the pattern, so deleting the row goes RED.

## Reproduce

```bash
cd dwarves-kit && bash tests/test-hooks.sh && bash tests/test-meta.sh
```

VERDICT: PASS
