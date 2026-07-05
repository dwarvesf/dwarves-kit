# Implementation notes: board-bridge writeback (SPEC-149)

Delta from the spec / the original sub-goal contract only; see
`docs/specs/SPEC-149-board-bridge-writeback.md` for the full design record.

## 2026-07-05 05:35 Snapshot refresh: only `hermes_status`, never `row_hash` -- a design decision the contract didn't spell out

**Context**: the sub-goal contract says "refresh the snapshot after a successful apply" without
specifying which fields. My first instinct was to recompute a NEW `row_hash` for the target
status (since that's what the git content will eventually become) and write both fields.

**Decision**: refresh ONLY `hermes_status` (to the live value observed); pass `row_hash` through
UNCHANGED from what the snapshot already recorded.

**Why**: the writeback commit lands on a HELD, unmerged `chore/board-sync` branch -- the actual
git SoT (the default branch `board mirror` reads) has NOT changed yet. If `row_hash` were
refreshed to the future/target value, the next `board mirror` run would compare that refreshed
hash against the STILL-unmerged default branch's real (unchanged) content, find a mismatch, and
treat it as a fresh git-side CHANGE -- a confusing, incorrect "content updated" comment posted to
Hermes for a change that hasn't actually landed anywhere yet. Leaving `row_hash` untouched keeps
`board mirror`'s existing idempotence correct through the whole HELD-PR window; refreshing only
`hermes_status` is what stops writeback itself from re-diffing (and re-PR-ing) the SAME Hermes-side
move on a second run before the PR merges.

**Alternatives considered**: (a) refresh both fields -- rejected for the reason above (breaks
mirror's idempotence pre-merge). (b) refresh neither field -- rejected: a second `board writeback`
run before the PR merges would find the SAME delta again (live status still differs from the
STALE recorded `hermes_status`) and open a SECOND, duplicate PR for the identical change, directly
contradicting "ONE PR per sync run" as a steady-state property, not just a per-invocation one.

**Impact**: a genuine, documented limitation results (see the spec's "Known limitation"): if the
operator CLOSES the held PR without merging, the snapshot has already "forgotten" the delta (its
`hermes_status` matches live), so writeback will not re-propose it on its own. Recovery requires
moving the Hermes card again. This is accepted, not fixed, per the sub-goal's explicit scope
("bidirectional merge logic beyond the hash rule" is out of scope).

## 2026-07-05 05:40 A real portability bug: physical vs logical path mismatch broke the worktree-relative-path computation

**Context**: `_apply_group` computes `rel="${backlog_file#"$repo_root"/}"` to know the BACKLOG.md's
path relative to its repo root, so it can locate the same file inside the scratch worktree.

**Decision**: canonicalize the registry's `path` value to its PHYSICAL form (`pwd -P`, not plain
`pwd`) immediately after resolving `~`, in `cmd_diff`, before it is ever compared against
`repo_root`.

**Why**: `_repo_root_for` (sourced from `board-mirror.sh`) resolves a repo root via `git rev-parse
--show-toplevel`, which git always returns as a PHYSICAL path (symlinks resolved). On macOS,
`$TMPDIR` sits under the `/var -> /private/var` symlink, so a fixture's registry path (e.g.
`$TMPDIR/repo/_meta/BACKLOG.md`) stayed LOGICAL (`/var/folders/...`) while `repo_root` came back
PHYSICAL (`/private/var/folders/...`). The string-prefix strip in `rel=${backlog_file#"$repo_root"/}`
then silently failed to match at all (no error -- bash's `#` prefix-removal is a no-op when the
prefix doesn't match), leaving `rel` as the WHOLE absolute path, which then produced a nonsensical
double-rooted path inside the scratch worktree (`$wt/$rel` = `$wt` + a second absolute path
concatenated onto it) and the subsequent `bash backlog.sh set` call failed with "no Active-queue
row" because it was looking at a path that didn't exist.

**Impact**: caught IMMEDIATELY by this build's own first live smoke test (not by the automated
suite in isolation -- the suite's `mktemp -d` fixtures hit the exact same macOS symlink, so the
fix landed before the suite was even written in its final form). This is exactly the kind of bug a
purely-mocked unit test (with hand-typed paths that happen to already be physical) would miss;
running the tool end-to-end against a REAL `mktemp`-created macOS path is what surfaced it.

## 2026-07-05 06:10 `if ! cmd; then rc=$?; fi` captures the WRONG exit code (bash gotcha, caught in `board.sh`'s wrapper)

**Context**: `cmd_writeback` (in `lib/board/board.sh`) needs to propagate `board-writeback.sh diff`'s
real exit code (0, or nonzero on a missing/corrupt snapshot) back to the caller.

**Decision**: use `if cmd; then rc=0; else rc=$?; fi` (capturing `$?` only in the `else` branch,
after the negation-free condition), NOT `if ! cmd; then rc=$?; fi`.

**Why**: bash's `$?` inside an `if ! cmd; then ...; fi` block reflects the NEGATED (`!`-inverted)
truth value of the whole `if` test, not `cmd`'s own original exit code. Concretely: `if ! false;
then echo $?; fi` prints `0`, not `1`. This is exactly the pattern `lib/board/board-mirror.sh`'s
`cmd_apply_plan` already documents for its own `if out=$(...); then rc=0; else rc=$?; fi`
construction (needed there so `set -e` does not abort the whole script on a nonzero command
substitution); this build hit the SAME gotcha independently in `board.sh`'s wrapper, in the `!`
form specifically, and the automated suite (which asserts `board.sh writeback`'s exit code
directly for the missing/corrupt-snapshot NCs) caught it immediately -- the exit code always read
back as 0 regardless of the actual failure until fixed.

**Impact**: without this fix, NC5's contract requirement ("explicit error, exit nonzero") would
have silently degraded to "explicit error printed, but exit 0" -- the message was always right,
only the exit code was wrong, which is exactly the kind of half-fixed bug that looks fine in a
human's terminal but breaks any caller (a cron job, a CI gate, `set -e`-guarded automation) that
checks the exit code rather than grepping stderr.

## 2026-07-05 06:30 Reverse state mapping is deliberately lossy, and `ready -> claimed` was the least-bad choice among four candidates

**Context**: the sub-goal contract's `## Design` section doesn't specify what a `ready`-status
Hermes card should reverse-map to on the git side, since `ready` is the forward-mapped landing
spot for FOUR distinct git states (`claimed`/`speccing`/`validated`/`executing`).

**Decision**: `ready -> claimed`, documented explicitly as "the honest nearest-available state",
not a claim of fidelity.

**Why**: writeback cannot know, from the Hermes side alone, which of the four the operator
"meant" when they moved a card to `ready` (Hermes has no sub-state to disambiguate them -- this is
SPEC-147's own finding, not new). `claimed` is the least presumptuous of the four: it says "this is
now being worked", without asserting a spec exists (`speccing`), that a spec was approved
(`validated`), or that build is actively running (`executing`) -- claims the Hermes side has no way
to actually verify. This mirrors the forward map's own honesty posture (falling back to `ready`
rather than inventing a distinction the CLI cannot hold), applied to the reverse direction.

**Alternatives considered**: (a) reject `ready` entirely as unmappable (treat it as illegal, same
as `todo`/`running`) -- rejected: this would make the whole `ready` equivalence class permanently
write-only from git to Hermes, defeating the actual point of building a writeback leg at all (the
MOST common real-world operator action -- "I'm now working on this" -- would never flow back).
(b) reverse-map to `executing` (the "most active" end of the range) -- rejected: strictly more
presumptuous than `claimed`, and a card an operator just glanced at and moved to `ready` almost
certainly hasn't started active build work yet.
