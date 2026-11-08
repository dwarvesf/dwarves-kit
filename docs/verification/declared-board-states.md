# Verification -- declared-board-states

SPEC-417: the board row machine is declared once in `lib/board/states.tsv`, and every reader derives from it. `backlog.sh` gains `states --class` and `machine`, and `set` prints a notice on a move out of a terminal state.

| Check | Command | Result |
|---|---|---|
| New suite | `bash tests/test-board-states.sh` | 17/17 passed |
| Changed suites | `bash tests/run-all.sh --changed` | all 68 suites passed |
| Independent review (Opus, correctness lens) | read-only reviewer on the branch diff | 1 HIGH (SIGPIPE on large boards) + 1 LOW fixed; both pinned by tests |
| Negative control 1 | restore the early `exit` in the reopen lookup | case 6b FAIL `rc=141`; restored |
| Negative control 2 | plant a literal active set in `sources/hermes.py` | case 5 FAIL `hardcoded vocabulary`; restored |

## Green run

The real primary flow on a scratch board: an agent reads the machine, then a hand repair reopens a shipped row.

```
$ bash lib/board/backlog.sh machine
state	class	next
queued	active	claimed
claimed	active	speccing executing
speccing	active	validated executing
validated	active	executing
executing	active	shipped
shipped	terminal	-
parked	hold	queued claimed speccing validated executing
dropped	terminal	-
$ backlog.sh set ID-001 queued "repair"   (row was shipped)
board set: ID-001 reopens from terminal 'shipped' to 'queued'
ID-001 -> queued
exit=0
```
