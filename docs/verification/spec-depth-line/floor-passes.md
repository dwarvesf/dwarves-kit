# Floor passes (AC6 live check)

Two fresh Sonnet subagents ran the `--floor` pass (lens 1 Coverage, lens 2 Oracle, one pass) on inline plans. The seeded-gap plan has AC2 with no test row, case 1 "works" / "run the tool", case 2 "should work" / TBD. The good plan covers both ACs, with concrete proofs and a named negative control per case.

| Plan | Lens 1 | Lens 2 | CRITICAL findings | Verdict |
|---|---|---|---|---|
| seeded gap | 2/10: AC2 has no test (CRITICAL) | 1/10: case 1 and case 2 have no negative control (CRITICAL), AC2 has none (CRITICAL) | 4 | RECONSIDER (not SOLID) |
| good | 6/10 | 6/10 | 0 (two HIGH coverage gaps, one HIGH oracle weakness) | REVISE (no CRITICAL) |

Both replies carried `Scope: floor (coverage + oracle)`. The floor bites on the seeded gap and does not raise a CRITICAL on the good plan.
