# Implementation notes: handoffs.sh skips archive/ and nested .claude/ (SPEC-333)

Delta from the spec only; see
`docs/specs/SPEC-333-handoffs-archive-skip.md` for the full design record.

## Reserved spec number was 333, not 332

`bash lib/spec/spec-next.sh reserve` returned 333 on the first call in this worktree. No
prior file at `docs/specs/SPEC-332-*.md` exists in this worktree; 332 was presumably reserved
by another concurrent run elsewhere. Not investigated further, out of scope for this task.

## Lane corrected from tiny to normal after the fact

The initial spec draft (phase 1) set `Lane: tiny`. That was wrong: `tiny` lane means "one
obvious edit, no spec" per `docs/WORKFLOW.md`'s lane table, but this task already went through
a full `/kit:spec` + fresh-context `/kit:spec-validate` cycle (two rounds, NEEDS REVISION then
APPROVED). Running `bash lib/classify/lane-classify.sh classify "<task text>"` independently
returned `normal`. Fixed in the warning-fold commit. Also matters for `## Gate ledger entries
below: normal's ship-gate-enforced (measure-twice) rows are `spec`, `build`, `ship`, not the
full lane's much longer list.

## Approach 2 (naive `-not -path` append) is a real, verified regression, not a hypothetical

Before picking the `-prune`/`-name` fix, I mechanically checked what a naive
`-not -path '*/archive/*' -not -path '*/.claude/*'` append would do to the existing
`.claude/handoffs` scan root: `$d` for that root is literally `<repo>/.claude/handoffs`, so the
glob matches the scan root's OWN path, not just a nested subdirectory, and the whole root goes
empty. The first spec-validate round (NEEDS REVISION, critical 1) caught this as a live-data
regression (14 of 14 lost on ops-toolkit). Fixed by switching to `-prune` keyed on the visited
node's own basename, which never re-examines the start point's ancestor path components.

## design-record: not design-bearing

`bash lib/gate/gate-ledger.sh record handoffs-archive-skip design-record ran "design-bearing=no pass"`
was recorded by the fresh-context validator's Reviewer 6 pass (no new component, no
schema/data-model change, no external integration, one existing internal function's filter
logic). Not re-recorded here per the coordinator's instruction.
