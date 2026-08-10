# Proof of done: queue submit-detection fix (the 3-for-3 stranded-goal glitch)

Profile: fix   Proof class: behavioral

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | A dropped Enter with the goal rendered tail-first (no `/goal` substring in the pane) is detected as still-pending and re-Entered until the input clears | PASS | R1 (T9) |
| 2 | A bare prompt exits after one Enter, no retry storm | PASS | R1 (T10) |
| 3 | Reverting only `lib/queue/queue.sh` reproduces the stranding in miniature: the loop exits after one dropped Enter and the pending input survives (negative control) | PASS | R2 |
| 4 | Queue suite delta vs master is zero (the 3 pre-existing NC failures are identical on both) | PASS | R3 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | `_mux_submit`'s still-pending check matched the literal `[>❯]\s*/goal`, but a long typed goal renders TAIL-first in the input box (`❯ (or "EXIT_SIGNAL...`), so `/goal` never appears at the prompt. The check reported "submitted" after the first (dropped) Enter and the row sat stranded with no journal entry. Three consecutive live runs reproduced it; one manual Enter unstuck each. New check: still pending iff any line renders a prompt char with content after it (`^\s*[>❯]\s*[^\s]`); a bare prompt means submitted. Warn on exhausting the 5 tries instead of silent success. |
| Where | `lib/queue/queue.sh` `_mux_submit`; `tests/fixtures/queue/fake-mux` gains a `.pending` counter simulating the dropped-Enter state; `tests/test-queue.bats` T9/T10. |
| Asymmetry argument | False "still pending" costs at most 4 harmless extra Enters on an empty prompt; false "submitted" strands the row. The check errs pending. |
| Reversibility | `git revert`; behavior-only, no state. |

## 3. Confirmation (runs)

| Run | Command | Exit | Verdict |
|---|---|---|---|
| R1 | `bats tests/test-queue.bats -f "T9\|T10"` | 0 | PASS (2/2) |
| R2 | `git stash push -- lib/queue/queue.sh` then re-run T9 | 1 | RED-as-expected, then restored green |
| R3 | full `bats tests/test-queue.bats` on this branch AND on a pristine master worktree | - | identical failure sets (NC2, NC6, NC7 pre-existing on both; delta zero) |

## 4. Run detail

### R1 GREEN
```
ok 1 T9 submit-retry: tail-rendered pending input is re-Entered until clear
ok 2 T10 submit-bare-prompt: bare prompt exits after one Enter
```
T9 seeds `pending=2` (two dropped Enters), asserts the pending state clears and exactly 2 Enters were sent. Its premise guard asserts the stuck rendering contains NO `/goal` substring, the exact condition that blinded the old regex.

### R2 NEGATIVE CONTROL
```
$ git stash push -q -- lib/queue/queue.sh    # old detection back
not ok 2 T9 submit-retry: tail-rendered pending input is re-Entered until clear
#   `[ ! -f "$QSTUB/s7.pending" ]                    # input eventually cleared' failed
$ git stash pop -q
ok 2 T9 submit-retry: tail-rendered pending input is re-Entered until clear
```
The failure lands on "input eventually cleared": with the old regex the loop exits after one dropped Enter believing it submitted, leaving the goal pending, the live failure mode in miniature.

### R3 delta-zero
```
branch: not ok 9 NC2 / not ok 13 NC6 / not ok 14 NC7
master: not ok 9 NC2 / not ok 13 NC6 / not ok 14 NC7
```
Identical sets. The three pre-existing failures are false-done/stall guards and are filed as their own board row; this branch neither fixes nor worsens them.

## 5. Reproduce

```
bats tests/test-queue.bats -f "T9|T10"
```
