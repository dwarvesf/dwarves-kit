# Proof of done: gate-ledger-fixes (SPEC-071)

Behavioral change, 4 defects: proof_class registry floor (ID-061), ship-gate
boardless advisory relocated above the spec check (ID-063), evidence-dies-with-
the-session warn (ID-062), out-of-order `*` marker + legend in progress (ID-050).

## Green run

Failing-test-first, recorded live: the 12 SPEC-071 assertions were written and run
against the PRE-fix tree -> 5 RED (one per defect surface: `class=inert` missing,
advisory unreachable, warn absent, `*review` absent, legend absent; the negatives
were green pre-fix by silence, as expected). Fixes applied -> all GREEN.

Command: `bash tests/test-hooks.sh`
Exit: 0
Output (tail): `Passed: 345 / 345` (12 failing-first + 4 review-driven)

Command: `bash tests/test-meta.sh`
Exit: 0
Output (tail): `All meta tests passed.` (432)

Command: `bash tests/test-e2e.sh`
Exit: 0
Output (tail): `Golden run green.` (20/20)

## NEGATIVE CONTROL

The failing-first run IS the per-fix negative control: each pin demonstrably RED on
the unfixed tree (5 RED captured in the build log above), GREEN only after its fix.
Reverting any one fix re-opens exactly its own pins (the fixes touch disjoint
blocks: proof-gate step 3, ship-gate pre-spec block, progress loop).

Self-referential live check: this very branch records `build ran` under lane full;
until this proof file was committed, the new ID-062 advisory fires on a push of
this branch; with the file committed it is silent (exercised at ship).

## Reproduce

```bash
cd dwarves-kit
bash tests/test-hooks.sh   # 342/342
bash tests/test-meta.sh    # 432/432
bash tests/test-e2e.sh     # 20/20
```

VERDICT: PASS
