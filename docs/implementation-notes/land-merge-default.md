# Implementation notes: land/merge default-branch merge cycle

Delta from `docs/specs/SPEC-375-land-merge-default.md` only.

## `merge --verify=` parses to no verify command

The spec's "missing value exits 64" covers a bare `--verify`. `--verify=` parses to an empty string, which means no verify command runs, matching how `land --verify=` already parses. Chosen for symmetry rather than adding a third exit path for a flag shape the spec never names.

## The squash fallback still runs after a refused re-merge (returns 4 and 5)

A refused re-merge (a conflict beyond the union-marked files, or a branch that already contains `origin/<default>`) maps to 1 inside `_remerge_push` so `cmd_merge`'s existing fallback machinery still fires, keeping the pre-spec refusal lines unchanged. Only a 2 (a restore that could not finish) skips the fallback: a checkout left mid-merge is not safe to reason over, so the run exits 2 and names the worktree for a human.

## --no-overwrite-ignore is a hint, not a refusal, under merge-ort

The review asked for `git merge --no-overwrite-ignore` so a merge that would clobber an ignored file refuses. The flag stays on the call, but git 2.55's merge-ort backend ignores it and overwrites the file anyway, so `_merge_default` also refuses before the merge when the incoming diff touches a recorded ignored path; that pre-flight check is what actually protects the file today.
