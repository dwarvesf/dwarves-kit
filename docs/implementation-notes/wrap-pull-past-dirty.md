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

## 2026-09-13 `_usage` now prints two more header lines
- Context: `_usage` is `sed -n '2,25p'` over the file header, and the knob needed a clause in the invariant sentence that says the verbs never touch a dirty file.
- Decision/Change: the clause was added and the range moved to `2,26p`.
- Why: without the range change `bin/wrap --help` ended mid-sentence on the default-branch note.
- Impact: `--help` output grows by nothing; it just stops truncating.
