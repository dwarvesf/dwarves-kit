# Light passes (AC6 live check)

Three fresh Sonnet subagents ran the `--light` pass (lens 1 Coverage, lens 2 Oracle, one pass) on inline plans. Verdict rule: SOLID when there is no CRITICAL and no HIGH finding, otherwise REVISE (RECONSIDER when an AC cannot be tested at all). The first two runs predate that rule and gave their own verdict; the table restates them under it.

| Plan | Lens 1 | Lens 2 | CRITICAL | HIGH | Verdict under the rule |
|---|---|---|---|---|---|
| seeded gap (AC2 untested, "should work" oracles) | 2/10 | 1/10 | 4 | several | RECONSIDER |
| good plan, 4 cases | 6/10 | 6/10 | 0 | 3 | REVISE |
| fixed plan, 6 cases (added missing-file, all-defaults, partial, named reverts) | 7/10 | 7/10 | 0 | 2 | REVISE |

The light pass bites on the seeded gap: CRITICAL on the uncovered AC and on the missing negative controls. It does not raise a CRITICAL on either good plan. No run reached SOLID: under the HIGH-blocks rule the reviewer keeps finding a HIGH (a key covered once, a weak oracle) on plans that an author would call good. A SOLID light verdict is not demonstrated live. Tune the rule (for example HIGH only when it names an AC gap) if that proves too strict in use.
