# Implementation notes: board work

Only decisions, deviations, tradeoffs and open questions that differ from the spec.


## Deviations and decisions

- Zero deviation from the spec's contract (flags, JSON schema 1, rules).
- Sources write normalized JSON files under one `mktemp -d` dir and the join is a single jq program, instead of five shell functions piping lines. Same five source readers; the join reads only those files.
- Shipped board rows with no draft or no branch count in `unchecked_shipped` and are not listed. A shipped row whose branch resolves is always listed only when it can hold DONE-UNSEEN (ledger has `ship ran`); shipped with a live branch and no ship record shows rung by ledger and no flag.
- Table WORKTREE cell is the worktree directory basename, not the full path (the full path is in `--json`).
- Negative control 4 mutates the "shipped and unresolvable is unchecked, not listed" branch rather than the wrap condition named in the spec's dry trace, because the code never had a wrap condition to keep.
- Negative controls 1 and 3 catch different cases than the dry traces name (`not_in_orca_no_terminal`, `rung_ladder`); the dry-trace mutation 1 on `no_worktree_indeterminate` is unreachable since a missing worktree never enters the orca rule.

## Open questions

None.
