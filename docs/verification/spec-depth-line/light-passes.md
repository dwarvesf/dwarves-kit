# Light passes (AC6 live check)

Three fresh Sonnet subagents ran the `--light` pass (lens 1 Coverage, lens 2 Oracle, one pass) on inline plans. Verdict rule: SOLID when there is no CRITICAL finding; HIGH findings are advisory (the author addresses each or writes one line why not); RECONSIDER when an AC cannot be tested at all. The runs predate the final rule (they were told REVISE on any HIGH); the table restates them under it.

| Plan | Lens 1 | Lens 2 | CRITICAL | HIGH | Verdict under the rule |
|---|---|---|---|---|---|
| seeded gap (AC2 untested, "should work" oracles) | 2/10 | 1/10 | 4 | several | RECONSIDER |
| good plan, 4 cases | 6/10 | 6/10 | 0 | 3 | SOLID, 3 advisory HIGH |
| fixed plan, 6 cases (added missing-file, all-defaults, partial, named reverts) | 7/10 | 7/10 | 0 | 2 | SOLID, 2 advisory HIGH |

The light pass bites on the seeded gap: CRITICAL on the uncovered AC and on the missing negative controls. It raises no CRITICAL on either good plan, so both reach SOLID. The SOLID rows are a restatement of the recorded findings under the final rule, not a fresh run.
