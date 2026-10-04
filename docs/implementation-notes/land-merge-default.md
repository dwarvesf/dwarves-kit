# Implementation notes: land/merge default-branch merge cycle

Delta from `docs/specs/SPEC-378-land-merge-default.md` only.

## `merge --verify=` parses to no verify command

The spec's "missing value exits 64" covers a bare `--verify`. `--verify=` parses to an empty string, which means no verify command runs, matching how `land --verify=` already parses. Chosen for symmetry rather than adding a third exit path for a flag shape the spec never names.

## The squash fallback still runs after a refused re-merge (returns 4 and 5)

A refused re-merge (a conflict beyond the union-marked files, or a branch that already contains `origin/<default>`) maps to 1 inside `_remerge_push` so `cmd_merge`'s existing fallback machinery still fires, keeping the pre-spec refusal lines unchanged. Only a 2 (a restore that could not finish) skips the fallback: a checkout left mid-merge is not safe to reason over, so the run exits 2 and names the worktree for a human.

## --no-overwrite-ignore is a hint, not a refusal, under merge-ort

The review asked for `git merge --no-overwrite-ignore` so a merge that would clobber an ignored file refuses. The flag stays on the call, but git 2.55's merge-ort backend ignores it and overwrites the file anyway, so `_merge_default` also refuses before the merge when the incoming diff touches a recorded ignored path; that pre-flight check is what actually protects the file today.

## Ported onto #853 modules

The branch was written against the monolithic `wrap.sh` and `test-wrap.sh`. After origin/master split both (#853), the change was re-applied by moving each function to its owning module with the reviewed body unchanged. The merge cycle went to `wrap-common.sh` because `land` and `merge` both call it, and that file already selects every wrap suite in `bin/test-affected`. `wrap-rebase.sh` keeps `_rb_resolve`. A `wrap-rebase.sh` edit now also selects the land and merge suites, since the cycle depends on the resolver.

The spec is renumbered to SPEC-378: #853 took 374. The spec body still names the monolith paths (`lib/wrap/wrap.sh`, `tests/test-wrap.sh`) in its design record and grounding, left as the reviewed text.
