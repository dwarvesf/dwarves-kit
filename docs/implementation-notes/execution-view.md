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

## Final round: file-activity state and the ship window (lead-approved)

- `agent.source` (`orca`, `files`, `none`) is additive, still schema 1. With no orca row a worktree's state comes from file activity: newest mtime of the `git status -uall` paths plus HEAD's commit time when the branch has its own commits past the default branch. No activity stays `unknown`, and orca absent, remote-host and no-terminal cases never fall back (orca itself is the missing key, so the view does not guess).
- PARKED from files carries the advisory reason `files-idle`. That breaks the old rule "reasons non-empty exactly when INDETERMINATE": now INDETERMINATE means a reason other than `files-idle`. Test and contract table updated.
- `stat` is portable by probing GNU `stat -c %Y` first, then BSD `stat -f %m`. The suite's GNU-tools pass covers the GNU branch, the plain pass the BSD one. Tests set mtimes with `touch -t` from a GNU or BSD `date` conversion.
- `--since` decision, needs the lead's eye: a board row has no date, so only rows linked to a ledger ship record can sit inside a window. A shipped row with a draft and a ship record dated inside the window, with no branch left, counts in `unchecked_shipped` and ages out after N days. Rows with no draft or no ship record cannot be dated and move to a new `undated_shipped` key (plus `since_days`), so the live 206 no longer reads as 206 unchecked. If the lead wanted them counted, undated rows can go back into `unchecked_shipped`.
- Reading file activity is read-only: `git --no-optional-locks status`, checked by a hash test.

## Open questions

None.
