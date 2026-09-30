# Implementation notes: board work

Only decisions, deviations, tradeoffs and open questions that differ from the spec.


## Deviations and decisions

- Zero deviation from the spec's contract (flags, JSON schema 1, rules).
- Sources write normalized JSON files under one `mktemp -d` dir and the join is a single jq program, instead of five shell functions piping lines. Same five source readers; the join reads only those files.
- Shipped board rows with no draft or no branch count in `unchecked_shipped` and are not listed. A shipped row whose branch resolves is always listed only when it can hold DONE-UNSEEN (ledger has `ship ran`); shipped with a live branch and no ship record shows rung by ledger and no flag.
- Table WORKTREE cell is the worktree directory basename, not the full path (the full path is in `--json`).
- Negative control 4 mutates the "shipped and unresolvable is unchecked, not listed" branch rather than the wrap condition named in the spec's dry trace, because the code never had a wrap condition to keep.
- Negative controls 1 and 3 catch different cases than the dry traces name (`not_in_orca_no_terminal`, `rung_ladder`); the dry-trace mutation 1 on `no_worktree_indeterminate` is unreachable since a missing worktree never enters the orca rule.

## Review round

- The `runid_lines` tr set had a reversed range under GNU tr (`._-\n`), so every slug normalized empty on CI. The dash now goes last. The suite reruns itself once with the coreutils gnubin first on PATH, and prints a visible SKIP when that directory is absent.
- Branch fallback: a `worktree ps` row is borrowed by branch only when its canonical path is under the repo root or code root and exactly one row matches.
- A shipped row that resolves no branch but holds a ship record in the ledger is finished: dropped, not counted. Only no-draft and no-ship-record rows count in `unchecked_shipped`.
- `orca worktree ps` runs under `timeout`/`gtimeout` (`ORCA_TIMEOUT_S`, default 10) when one exists; a timeout is `orca=error`. Without either tool the call is unbounded.
- Date-led roadmap lines no longer read as legacy sub-goals (the slug part must start with a letter).

## Usefulness amendment (lead-approved), deltas from the original spec

- New `origin` value `worktree`: every live worktree not joined to a board or mega item is its own item, so running agents appear even when board rows have no drafts. The main checkout of each repo is excluded. Still schema 1.
- Two new item keys, `lane` and `started` (null when unclaimed), from `goal-registry.sh list`; only its SLUG is used and it joins the worktree basename. A claim with no live worktree is `INDETERMINATE(no-worktree)`. The table gains a LANE column.
- A worktree item counts as in progress, so it can be PARKED; it has no DONE-UNSEEN.
- A mega branch that is also a board branch lists twice, once per origin. Documented, not deduplicated.

## Open questions

None.
