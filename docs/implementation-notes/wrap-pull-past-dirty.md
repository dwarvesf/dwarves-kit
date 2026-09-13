# Implementation notes -- wrap-pull-past-dirty

Deltas from the draft at `.claude/goals/wrap-pull-past-dirty.md` and from SPEC-286. Nothing here repeats what the spec already states.

## 2026-09-13 The blocking set is computed, not parsed out of git's refusal
- Context: the draft says only the files git names in its `would be overwritten by merge` list may be stashed. Reading that list means running the pull, letting it fail, parsing the captured output, and pulling a second time.
- Decision/Change: `_ff_blocked_into` computes the set as `dirty tracked` intersected with `changes between HEAD and @{u}`, before the first pull. One pull attempt, no output capture, no retry.
- Why: `wrap.sh`'s own header states the verbs never retry a failed git call, and a parse path would have broken that for the sake of a list git derives from the same two facts. The intersection is the per-entry up-to-date test git itself applies while reading the two trees of a fast-forward, so the sets agree.
- Alternatives considered: tee the pull output through `run` and parse `Your local changes to the following files` (rejected: a second pull, plus a printed `FAILED` line before a run that then succeeds).
- Impact: the equivalence is asserted, not assumed. The knob-off case proves git names the file, and the knob-on case on the same fixture reports `stashed 1 dirty tracked file(s)` while a second dirty file outside the incoming commit stays dirty.

## 2026-09-13 No union-conflict resolver, because the pop never conflicts on a union file
- Context: the draft asks for a pop conflict on a `merge=union` file to resolve by keeping both sides.
- Decision/Change: no such branch exists. Any conflicted file keeps the markers, keeps the stash, and reports `POP CONFLICT`.
- Why: `git stash pop` performs a three-way content merge that honours `.gitattributes`, so a union-marked file resolves inside the pop and never reaches the conflict list. A branch that cannot be reached cannot be tested, and untested recovery code on a shared checkout is worse than none.
- Alternatives considered: write the resolver anyway and mark it defensive (rejected: it would need `git add` then `git reset` to restore the unstaged shape, on a file wrap did not write).
- Impact: the union case is covered by a test that asserts the absence of a conflict and the presence of both sides, which is the proof the branch is unnecessary.

## 2026-09-13 The knob path refuses a dirty index
- Context: the draft's constraints do not mention the index.
- Decision/Change: the knob branch is entered only when `git diff --cached --name-only` is empty, matching the guard the union-carry path already applies.
- Why: `git stash pop` without `--index` restores staged changes as unstaged. On a shared checkout that silently unstages another session's work.
- Impact: a staged path keeps today's behaviour and prints the existing index note.

## 2026-09-13 Review found the intersection false in four directions; three were fixed, one is documented
- Context: the correctness lens reproduced four cases where the computed blocking set disagrees with what git refuses. Two turned a knob-off exit 0 into a knob-on exit 2 with damage: a worktree-deleted path was stashed and popped into an unmerged index, and a dirty submodule gitlink produced a stash record for a stash that was never created.
- Decision/Change: `_ff_blocked_into` now skips any path that is not a regular file and passes `--no-renames` on the incoming diff. `_stash_blocked` records the commit `refs/stash` moved to and returns empty when it did not move, so a push that saved nothing degrades to the knob-off pull instead of reporting the operator's work lost.
- Why: each of the three is a one-line guard whose absence is a green-to-red regression inside the knob's own happy path. The fourth, `assume-unchanged` and `skip-worktree`, has no cheap exact fix; it makes the knob no-op and the pull report `FAILED`, which is knob-off behaviour, so SPEC-286 states the limit rather than claiming exactness.
- Impact: four fixtures added, covering the rename, the worktree-deleted path, a diverged checkout, and a path holding a space and a bracket glob.

## 2026-09-13 The pop resolves the stash by commit, not by name or position
- Context: the security lens showed two ways the original `grep -m1 <name> | cut -d: -f1` resolution takes another session's entry: a pid that is a prefix of another run's pid, and any sibling push between the resolve and the pop, which shifts every index.
- Decision/Change: `_stash_blocked` prints the stash commit; `_unstash` walks `git stash list --format='%gd %H'` and pops only the entry whose commit matches.
- Why: the whole feature exists for a checkout other sessions write to. A handle that drifts under concurrency is the one thing this code cannot have.
- Impact: the failure line now names a recovery command against the recorded commit, so a stash that leaves the list is not lost.

## 2026-09-13 No signal trap around the pull
- Context: the review asked for a trap so an interrupt between the stash push and the pop cannot leave the blocking files only inside a stash.
- Decision/Change: no trap. The stash name prints before the pull, and `commands/wrap.md` step 5 carries the two-command recovery.
- Why: a trap that pops a stash while the shell unwinds is a second write to a checkout whose state nobody has looked at, in the one code path that touches files this session did not write. The material is not lost either way; it is a stash entry with a searchable name.
- Alternatives considered: `trap ... INT TERM` around the pull (rejected for the reason above); an EXIT trap (worse, it fires on every path including the ones that already popped).
- Impact: an interrupted run needs one operator command. Recorded here so a later session does not read the absence as an oversight.

## 2026-09-13 The blocking-file NOTE now says what the knob will do
- Context: with the knob on, the pre-existing `NOTE: ... so the pull aborts on: <files>` printed immediately above a stash line and a pull that landed.
- Decision/Change: the NOTE branches three ways: aborts (knob off), stashes (knob on, `--apply`), would stash (knob on, dry run).
- Why: a report that contradicts the run is the defect class this file is most careful about, and the dry run previously gave no warning that `--apply` would stash at all.

## 2026-09-13 Review: the run's own stash is found by its subject, not by where `refs/stash` moved
- Context: the shipped `_stash_blocked` read `refs/stash` before and after its push and recorded the new top as the run's own entry. The review reproduced a sibling `stash push` landing between the run's push and that read. The run then recorded the sibling's commit, popped and dropped the sibling's stash after the pull, left its own entry orphaned, lost the operator's local edit from the worktree, and reported `restored the stashed file(s) and dropped` with exit 0.
- Decision/Change: `_stash_blocked` walks `git stash list --format='%H %s'` and returns the commit whose subject ends in `: <run name>`. The push's exit code no longer gates the answer.
- Why: the subject is written by this run and no sibling writes it. A suffix match on the full run name has no prefix collision, which was the objection to the earlier `grep -m1 <name>` form. A push that failed after writing its entry still took the files, so only the list can say whether anything was taken.
- Impact: the pop is still by commit. One fixture stages the race with a git shim; against the shipped code it fails three assertions. SPEC-286 still says the commit is the one `refs/stash` moved to; this note is the delta.
- Open questions:
  - The `git stash list` to `git stash pop` window stays positional. `_unstash` resolves `stash@{N}` by commit and pops that ref a process spawn later; a sibling push in between shifts N. Git has no drop-by-commit, so the window can shrink (`stash apply <sha>`, then re-verify the ref and drop) but not close. Worth the extra write on a checkout other sessions share? Not changed in the review.
  - A dirty tracked file the incoming commits delete is stashed, the pull lands, and the pop is a modify/delete conflict every time, leaving `DU <path>` in the shared index with exit 2. Reproduced by hand. `--diff-filter=d` on the incoming diff would exclude the path and degrade to the knob-off `FAILED`. The spec accepts pop conflicts as an outcome, so this is a contract call, not a defect. Not changed in the review.

## 2026-09-13 The header names the stash in the write set, and `_usage` keeps its line range
- Context: `_usage` is `sed -n '2,25p'` over the file header. A first attempt added a parenthetical to the sentence that says the verbs never touch a dirty file, which pushed the last header line out of the usage window.
- Decision/Change: the write-set enumeration names `its pull-past-dirty stash` instead, and the paragraph was rewrapped to the same line count, so the range stays `2,25p`.
- Why: the enumeration is where a reader looks for what the verbs write, and the stash is a write. Naming it there is more precise than an exception clause on the invariant, and it costs no line.
