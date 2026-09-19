# Implementation notes: SPEC-304 wrap start verb

The delta from the spec at `docs/specs/SPEC-304-wrap-start-verb.md`.

## Decisions

- Placed `cmd_start` in `lib/wrap/wrap.sh` between `land` and `log`, so the open and close halves of the hand-made-worktree shape sit adjacent; dispatch mirrors the order. Precedent checked before building: `lib/goal/wt.sh start` (hardcoded `origin/master`, slug grammar, gate-ledger + board side effects; a different contract) and `lib/worktree-provision` (post-creation provisioner, never creates). Enhanced nothing, added the verb beside `land`.
- Slug rule is `${branch##*/}`: `feat/wrap-start` -> `.claude/worktrees/wrap-start`, the same `type/` strip gate-ledger's `rid` applies. A bare `<branch>` with no prefix uses the whole name.
- stdout carries only the resolved worktree path so `wt=$(bin/wrap start repo branch)` is directly usable; refusals and diagnostics go to stderr, matching `wt.sh`'s `echo "$wt"` contract.
- The same-name-on-origin check is a live `ls-remote --exit-code --heads` plus the tracking-ref read, run after `fetch origin <def>`: the fetch refreshes only the default ref, and `worktree add -b` never sees the remote, so a pushed-same-name branch would otherwise surface only as a non-ff refusal at push time.
- `git worktree prune` before the add, borrowed from `_wave_worktree` in `lib/queue/orchestrate.sh`, so a path deleted out-of-band cannot wedge `worktree add` on a stale admin entry.
- Exit codes follow the file's own grammar: 64 for usage (missing args, non-repo, invalid branch name), 1 for every pre-write refusal; a `worktree add` git refuses is also 1 with the target path, branch and base named.

## Open questions

- Whether `start` should run `worktree-provision` after the add is deliberately out of scope (spec "Out of scope"): the verb stays the minimal git step, and the provisioner is callable separately.
