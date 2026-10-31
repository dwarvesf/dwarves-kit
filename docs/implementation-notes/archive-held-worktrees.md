# archive-held-worktrees: implementation notes

Spec: `docs/specs/SPEC-415-archive-held-worktrees.md`. Validation round 1 warnings not folded into the spec, for the builder. Each line is a warning to handle during the build or log as a delta here.

## Reviewer 1
- Skip-worktree and assume-unchanged edits are invisible to `git status` and lost on removal: SKIP a worktree where `ls-files -v` shows an `S` or a lowercase tag.
- Sanitize every printed path with `tr '[:cntrl:]' '?'` before it reaches a report line.
- Validate the knob with `^[1-9][0-9]*$` and a length cap: `08` breaks bash arithmetic as octal.
- Cap the snapshot by path count or bytes before the push.
- Put `[skip ci]` in the snapshot and staged commit messages so an archive push starts no CI run.
- Regenerable ignored dirs may hold hand-placed files; this is an accepted risk, so log it in the delta.

## Reviewer 2
- Ambiguous push outcome: when the ref exists and equals HEAD on a clean worktree, count it as success; for a dirty worktree, name the wedge in the report.
- Add a push timeout and a size cap, and a Failure modes row for origin down.
- An empty mtime read counts as fresh; a deleted path uses its parent directory's mtime.
- Add a Failure modes row for two concurrent `apply` runs on the same repo.
- Re-run the ignored-blockers check after the push, before the removal.
- Check the exit code of the temp-index `add -A`.
- Order the cheap guards before the status walk, and short-circuit the idle-age read once one mtime is fresh.

## Reviewer 3
- A pid-less lock: override only lock reasons the Agent tool writes; keep any other locked worktree.
- Squash-merged detached worktrees: run `_absorbed` with the detached commit so they reach the merge-proof path.
- With reflogs off, `logs/HEAD` is absent; note the staleness fallback (admin `HEAD` and `commondir` only).
- `status --porcelain=v1 -z` rename records carry two NUL-separated paths; the parsers must consume both.

## Reviewer 4
- Touches misses `CHANGELOG.md`, `bin/**` and `docs/reference/**`.
- Untasked doc mentions to update: `bin/wrap:9`, `docs/reference/wrap.md:39`, `docs/reference/consumer-contract.md:88`, `lib/wrap/README.md:8`, `commands/wrap.md:160`.
- TASK-H is large; split it if it does not fit one session.
- The closed write set in the `wrap.sh` header must also name `config --remove-section` and the staged commit.
- Untested report lines: index.lock held, snapshot failed, origin holds X, checked out elsewhere, survived the removal, unresolvable.
- AC-16's control deletes two guards at once, so the read-back compare has no test of its own; add one.
- AC-26's control will not go red as written; grep a phrase from the new header paragraph instead of the flag name.
- Add a `status --porcelain=v1 -z` sample with a rename to `## Grounding`.
- The staged commit may be gold-plating; keep it only if the AC-5 fixture shows a real loss without it.
- The regenerable list misses `.next`, `build`, `coverage` and `lib/*/bin/*-rs`.
- AC numbering is out of order in the table (AC-29 to AC-33 follow AC-25); renumber at build time if the tests name rows by number.

## Reviewer 5
- Consider one shared `_archive_push` helper for both archive sweeps instead of duplicated push and read-back logic.
- Derive the regenerable list from land's `_LAND_IGNORED_BUILTIN` minus its local-config and secret entries, so the two lists cannot drift.
