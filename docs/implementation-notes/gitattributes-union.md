# gitattributes-union

Delta from the brief. The brief asked for a resolver on `bin/wrap apply`'s POP CONFLICT path
that would resolve a `merge=union` file's conflict hunks by hand.

## 2026-09-16 14:00 The premise was refuted, so the root cause shipped instead

Context: the brief said `git stash pop` uses the ordinary 3-way merge and leaves conflict
markers on a union-declared file, and that a session hand-resolved that four times.

Decision: no resolver. Declare the repo's append-only files `merge=union` in a
`.gitattributes` this repo never had.

Why, in three parts.

1. Measured. A fresh repo declaring one file `merge=union`, an upstream commit prepending a
   row and a local uncommitted row in the same hunk: `git stash push`, fast-forward,
   `git stash pop` exits 0, both rows land, no markers, the file stays unstaged. Union
   resolves during the pop. Binary-declared and NUL-byte variants do fail the pop, and they
   leave no markers, so a hunk resolver never sees them either.
2. Already asserted. `tests/test-wrap.sh` "knob on: a union-marked file blocked by the same
   pull resolves during the pop" has pinned this since the pull-past-dirty work, and
   `lib/wrap/wrap.sh` states the same contract in the `_unstash` comment.
3. The real cause. This repo carried no `.gitattributes` at all, so
   `git check-attr merge -- _meta/BACKLOG.md` answered `unspecified`. The board was never
   union HERE. The proposed `check-attr == union` gate would not have fired either. The
   sibling repo ops-toolkit declares the same file union and never needed the hand-resolve.

Alternatives: ship the resolver anyway as a safety net. Rejected, because no text-file path
reaches it, and unreachable code carries no proof.

Impact: the four-step hand procedure is gone at the source, and parallel branches adding a
board row now merge.

## 2026-09-16 14:20 The union declaration exposed a placement bug, so it is fixed here

Context: declaring `_meta/BACKLOG.md` union makes `_pull_default`'s carry-across-pull path
reachable for it. That path inserts carried lines below the first `---` line. The board has no
such line, so `_log_anchor_head_lines` returns 0 and the carried row prepended to line 1, above
the document title and outside the table.

Decision: `_carry_after_neighbour` places the carried block after the line that sat directly
above it in the local copy, used only when the anchor rule finds nothing.

Why: a row that `board capture` appended to a table belongs next to the row it followed. The
anchor rule keeps priority for every file that has an anchor, so `LAB_LOG`-shaped files are
untouched. ops-toolkit's board has a `---` at line 112 and never hit this.

Open questions: the carried row lands after its local neighbour, which for the fixture means
above the upstream row rather than below it. Git's own union driver would order it the other
way. Both are inside the table and neither loses a row, so the difference is cosmetic.
