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

## Commit-format hook strips SPEC- markers from subjects

Every commit subject in this worktree omits the `SPEC-333` tag (the repo's own
commit-format hook blocks a `SPEC-`/`TASK-`/phase marker in the subject line, over
72 chars for one attempt too). The spec number lives in the commit body instead.

## NC2's mutate-cmd ran from the session scratchpad, not a repo path

The negative control for approach 2 (the rejected naive `-not -path` append) needed a
multi-line awk rewrite as its mutate-cmd; passing it as an inline string through negctl's own
`bash -c "$mutate_cmd"` layer produced unreadable, escaping-fragile nesting. Wrote it as a
script file under this session's scratchpad instead, ran `bash lib/gate/negctl.sh . "bash
lib/session/tests/test-handoffs.sh" "bash <scratchpad path>/nc2-mutate.sh"`. The proof file
inlines the identical script content via a heredoc so the reproduction doesn't depend on this
session's ephemeral scratchpad path; verified byte-identical (function body only, comments
differ) against the script actually run.

## Proof file renamed: docs/verification/handoffs-archive-skip.md collides with a gitignore rule

`proof-ledger.sh check()` accepts any `docs/verification/*.md` the branch adds (matched by
regex, not an exact slug filename), so the proof file's name is not load-bearing beyond that.
The natural name, `docs/verification/handoffs-archive-skip.md` (matching the rid), is silently
gitignored: root `.gitignore` has `HANDOFF*.md` for wavefront/orchestrator runtime artifacts,
and this filesystem is case-insensitive, so `HANDOFF*.md` matches any basename starting with
`handoff`/`Handoff`/`HANDOFF` regardless of case, including this one, by coincidence of the
task's own subject matter. Renamed to `docs/verification/session-handoffs-archive-skip.md`
(confirmed un-ignored via `git check-ignore -v`), no content change otherwise.

## Operator override: name denylist replaced with a one-level scan

After the first implementation shipped the `-prune`/`-name` denylist (commit `359d8836`,
DEC-A), Han reviewed and rejected it: a denylist of four names breaks the next time a repo
archives into a fifth convention, and a subdirectory rule needs no list at all. Replaced with
`find "$d" -maxdepth 1 -type f -name '*.md'`: any file not sitting directly in a scan root
counts as consumed, regardless of the subdirectory's name. This also carries forward the
ancestor-path fix for free, a one-level scan performs no path-substring match at all, so an
ancestor segment above the scan root is structurally never examined. Verified before the
change: no repo under `~/workspace/tieubao` keeps a live handoff in a subdirectory of either
scan root. Spec DEC-A moved to rejected (approach 3), DEC-B added, Status reset to APPROVED.
Test suite cases `[16]`-`[19]` (built around the four-name fixture) replaced with cases
proving the design generalizes: an arbitrarily-named subdirectory (`old/`, not on any list)
excluded, plus the original named shapes still excluded, plus the ancestor case kept.

## Fold: re-validation warnings W1-W5 (post-VALIDATED)

The one-level design passed re-validation (critical=0, 5 warnings). Folded in the same
worktree, no new spec number:

- W1: the runtime `DEAD` message (`handoff_liveness`, line 143) said only "delete it"; a repo
  can now also move a handoff into a subdirectory to mark it consumed, so the message and its
  header passage both say "delete it or move it into any subdirectory". Test case `[10]`'s
  exact-match assertion updated to the new string.
- W2: `commands/start.md`'s kit:start line described the OLD `done/`/`_archive/` exclusion,
  stale after the one-level rewrite; reworded to the depth rule.
- W3: added Contract item 6 (and a DEC-B addendum): a handoff is one top-level `.md`; a
  multi-file bundle needs a top-level index file, since a subdirectory is consumed by design
  regardless of what it holds. The `handoff` skill that writes bundles is a separate touch,
  owned by the lead.
- W4: test case `[18]` (the `.claude/` ancestor) checked presence only; added the same
  exact-count assertion case `[17]` already had, so a silent extra/missing file would be
  caught there too.
- W5: added case `[20]`, a `done/`-ancestor fixture (`$(mktemp -d)/done/repo`). This is the
  decisive case for NC1: the pre-SPEC-333 filter's `-not -path '*/done/*'` matches a `done`
  segment ANYWHERE in the full printed path, including this ancestor, so NC1 must (and does)
  go red here specifically, not just on the arbitrary-name and named-shape cases. Spec test
  plan gained this as row 3 (renumbering the rows after it); the `## Negative control` section
  names it as NC1's decisive assertion.

Both negative controls re-ran clean after the fold: NC1 (revert to `194c89f0`) goes red on
cases `[16]`, `[17]`, `[19]`, and `[20]`; NC2 (apply the rejected denylist, `359d8836`) goes
red only on `[16]`/`[17]`/`[19]`, with both ancestor cases (`[18]` `.claude/`, `[20]` `done/`)
staying green, confirming the denylist's ancestor fix generalizes across segment names while
its name enumeration does not generalize across archive-folder names.

## Gate-ledger entries recorded post-implementation

`Build ran "bash lib/session/tests/test-handoffs.sh: smoke: all 22 passed"` was the first
`Build` record, before the fold above; a second `Build ran` records the post-fold state at 25
assertions. `spec`, `build`, `ship` are the three measure-twice gates the `normal` lane needs;
spec and its validate/design-record satellites were already recorded, and the fold's
re-validation is the same VALIDATED verdict, not a new spec gate. `Ship` was deliberately left
unrecorded: this session never pushes or merges (explicit instruction), and recording `Ship
ran` before an actual ship step would be a false ledger entry. Whoever eventually runs
`/kit:ship` on this branch records it then.
