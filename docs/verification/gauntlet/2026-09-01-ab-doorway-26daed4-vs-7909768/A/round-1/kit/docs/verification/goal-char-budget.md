# Proof of done: /goal char-budget pre-flight

Profile: fix   Proof class: behavioral

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | A pointer whose `/goal` line exceeds the 4000-char cap fails fast to journal `error`, no window opened | PASS | R1 (T11) |
| 2 | A normal-size pointer is unaffected: window opens, run completes | PASS | R1 (T12) |
| 3 | Reverting the length check alone reproduces the silent-strand shape on the same fixture (negative control) | PASS | R2 |
| 4 | Full queue suite delta vs master is zero | PASS | R3 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | The interactive `/goal` command refuses anything over 4000 chars, but nothing in the launcher checked this before typing. An over-budget pointer used to open a real window, type text `/goal` silently rejected, and sit there forever: no journal entry, no error, just an idle pane. Reproduced live once (ID-309's first attempt). New `QUEUE_GOAL_CHAR_LIMIT` (default 4000) is checked in `_launch_once` right after `_goal_line` computes the full text, BEFORE `_mux_open`, so an over-budget pointer never wastes a window at all, on either the first attempt or the single retry. |
| Where | `lib/queue/queue.sh`: one new env default, `_launch_once` reordered so `_goal_line` runs before `_mux_open`. `tests/test-queue.bats` T11/T12. |
| Reversibility | `git revert`; pure pre-flight check, no state. |

## 3. Confirmation (runs)

| Run | Command | Exit | Verdict |
|---|---|---|---|
| R1 | `bats tests/test-queue.bats -f "T11\|T12"` | 0 | PASS (2/2) |
| R2 | `git stash push -- lib/queue/queue.sh`, re-run T11 | 1 | RED-as-expected; restore green |
| R3 | full `bats tests/test-queue.bats` on this branch vs a pristine master worktree | - | identical failure set (NC2/NC6/NC7, filed as ID-468) |

## 4. Run detail

### R1 GREEN
```
ok 1 T11 goal-over-budget: fails fast to error, no window opened
ok 2 T12 goal-under-budget: unaffected, window opens and completes
```
T11 seeds a 4200-char pointer file (well past the ~4000 cap even after the `/goal ` prefix and
the EXIT_SIGNAL/draft-PR suffixes), asserts the journal verdict is `error` and that
`new-window slug=big11` never appears in the mux verb log.

### R2 NEGATIVE CONTROL
```
$ git stash push -q -- lib/queue/queue.sh
not ok 1 T11 goal-over-budget: fails fast to error, no window opened
#   `[ "$(jverdict big11)" = "error" ]' failed
$ git stash pop -q
ok 1 T11 goal-over-budget: fails fast to error, no window opened
```
Without the check, the oversized pointer no longer journals `error` (the old code has no
concept of the budget at all, so the run proceeds to open a window and, in the real product,
would sit there with the goal silently rejected).

### R3 delta-zero
Same three pre-existing failures (NC2, NC6, NC7) on this branch and on pristine master.

## 5. Reproduce

```
bats tests/test-queue.bats -f "T11|T12"
```
