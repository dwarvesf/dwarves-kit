# Verification -- a clean-room install test, and the operator-layer fence behind it

`tests/test-clean-room.sh` installs the kit into a bare HOME with a stripped PATH and drives adopt, a gate cycle and `config seams`. `tests/test-operator-pin.sh` fails a suite that reaches the config resolver without fencing off the host operator file. Both run under `tests/run-all.sh --all`, which CI already calls.

## Green run
```
Command: bash tests/test-clean-room.sh; bash tests/test-operator-pin.sh
Exit: 0
Output:
clean-room: 70 passed, 0 failed
operator-pin: 4 passed, 0 failed
Verdict: PASS
```
Regression: `bash tests/run-all.sh --changed --time` ran 73 suites. One failed, `test-board-work` (`board.sh help lists the verb`, a `| grep -q` under pipefail, hit while the host load average was over 100). Re-run alone three times it passed each time (`rc=0`). Earlier in the same session a first `--changed` run timed out `test-gate-ledger-plan-record` at 64s under the same load; it passed in the second run. The full `--all` glob was not run (AGENTS.md: the nightly job owns it).

## Negative control
Planted after the commit, each reverted with `git checkout -- <file>`.
```
Command: (a hardcoded read of the real operator kit.toml, echoed by lib/config/config.sh cmd_seams) bash tests/test-clean-room.sh
Exit: 1 (under mutation, RED expected)
Output:
  FAIL  every seam is default or absent (want '12', got '11')
  FAIL  no command output names the host (want '', got a line from the real operator kit.toml that names the maintainer's workspace)
clean-room: 68 passed, 2 failed
Verdict: PASS

Command: (lib/gate/gate-ledger.sh start writes a sibling of HOME and a file into the real ~/.local/state/dwarves-kit) bash tests/test-clean-room.sh
Exit: 1 (under mutation, RED expected)
Output:
  FAIL  after the full run: nothing written under the sandbox outside the allowed dirs (want '', got '.../kit-clean-room.ogDGXA/escaped-cr-cr90616x28339')
  FAIL  after the full run: no file in the real HOME carries this run's token (want '', got '/Users/<user>/.local/state/dwarves-kit/plant-b-cr-cr90616x28339')
clean-room: 68 passed, 2 failed
Verdict: PASS

Command: (drop the KIT_CONFIG_OPERATOR export from tests/test-pitch.sh) bash tests/test-operator-pin.sh
Exit: 1 (under mutation, RED expected)
Output:
  FAIL  no suite reaches the resolver unpinned (314 suites scanned) (want '', got 'tests/test-pitch.sh')
operator-pin: 3 passed, 1 failed
Verdict: PASS

Command: (drop the KIT_CONFIG_OPERATOR export from the worker block of tests/run-all.sh) bash tests/test-operator-pin.sh
Exit: 1 (under mutation, RED expected)
Output:
  FAIL  tests/run-all.sh does not pin KIT_CONFIG_OPERATOR
operator-pin: 3 passed, 1 failed
Restore: git checkout -- <each mutated file>; both suites green again (70 passed; 4 passed)
Verdict: PASS
```
The planted real-HOME file was a one-off scratch file made by the mutation; it was moved out of `~/.local/state/dwarves-kit` afterwards. The same assertions also run inside the clean-room test as self-checks against a stray entry and against leak strings.

## Rollback
Test and doc changes only, plus two comment lines in `kit.toml` and one `export` line in each of `tests/run-all.sh` and `bin/test-affected`. No state, no install on the live hosts changes: `git revert` of the merge commit restores the old tree, and the next `chezmoi apply` or pull needs nothing else.

## Not proven
- The plugin install path: it needs a running Claude Code, so no shell test reaches it.
- The CI matrix: the suite ran on the maintainer's macOS host only. Ubuntu is covered by reading (no BSD-only flags, `$BASH` linked into the stripped PATH, `gh` allowed present but logged out), not by a run.
- Writes to the real HOME are detected by name snapshot and a per-run token, not by a read-only mount. A write with no token in its name or content, into a dir the test does not watch, goes unseen.
- The operator-pin guard matches names, not a call graph: a suite that reaches the resolver only through a binary the pattern does not list is covered by the runner pin, not by the guard.
