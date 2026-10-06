# Verification -- orca-ac1-flake

`tests/test-orchestrate-orca.sh` case AC1 failed in the nightly regression on two of four nights. Root cause: the `claude-flip` fixture's heredoc was indented, so its `#!` sat in column 2. The kernel refuses to exec such a file (ENOEXEC), the calling bash re-runs it as a script in a forked child, and under load that child intermittently dies with `Segmentation fault: 11` (bash 5.3.20 from Homebrew, first on the nightly PATH). `orchestrate.sh` then reports `session for SG-01 exited nonzero` and `run` exits 1. The fixture now starts the shebang in column 0. A failed assertion also lands on the `FAIL` line, which `tests/run-all.sh` keeps (the old `[AC1] ... expected X got Y` detail line was dropped from the nightly log).

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | the flake reproduces with the old fixture | nightly-style env, 8 concurrent AC1 loops + 6 CPU burners | 12 of 120 runs failed, all 12 `Segmentation fault: 11` |
| AC2 | the fixed fixture does not flake under the same load | same harness | 0 of 240 runs failed |
| AC3 | the whole suite still passes | `run-all.sh --changed` | PASS (below) |
| AC4 | a failed assertion's detail reaches the run-all report | mutant run through `run-all.sh` | PASS (negative control) |

## Green run
```
Command: ab.sh tree-new 8 30   (env -i, PATH=$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin, ONLY=AC1, 6 busy loops alongside)
Exit: 0
Output:
tree=tree-new runs=240 failed=0 segfault=0
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
test-config-registry                           ok (37s)
test-kit-contract                              ok (3s)
test-no-personal-paths                         ok (3s)
test-no-scattered-ids                          ok (2s)
test-orchestrate-orca                          ok (104s)
run-all: all 6 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control
Revert: the same suite with the old indented fixture, same harness.
```
Command: ab.sh tree-fix 8 15   (identical env and load; only the fixture differs)
Exit: 0
Output:
tree=tree-fix runs=120 failed=12 segfault=12
Verdict: RED under the old fixture (10 percent), GREEN after the fix
```
A failing log from that run, now carrying the detail on the report line:
```
FAIL AC1: no flag exits 0 (run output: .../lib/queue/orchestrate.sh: line 1186:  1940 Segmentation fault: 11     "$CLAUDE_CMD" -p ... [orchestrate] session for SG-01 exited nonzero; stopping. ): expected '0' got '1'
```
Detail carriage: a mutant that makes the default path call `gh` (poison on PATH), run through `bash tests/run-all.sh --only test-orchestrate-orca` in a scratch copy:
```
      ! FAIL AC1: no flag: poison never called: expected '' got 'gh pr list gh pr list' | --backend claude: poison never called: expected '' got 'gh pr list gh pr list gh pr list gh pr list'
run-all: FAILED -> test-orchestrate-orca
```
The mutation lived only in the scratch copy; the committed tree is unmutated.

## Not proven
- Why bash 5.3.20 segfaults in the ENOEXEC fallback. The fixture no longer reaches that path; the bash bug itself is not investigated or reported upstream.
- The full nightly (`--all`) was not run; the AC1 failures on 2026-10-04 and 2026-10-06 are attributed by symptom match (same case, rc 1), since the nightly log never kept the detail line.
