# Verification -- negctl-setpgid-race

`negctl.sh --parallel` no longer lets bash's job-control `child setpgid (N to N): Operation not permitted` warning reach its reported output. The nightly regression of 2026-11-17 failed `tests/test-proof-negctl.sh` case [39] on that one extra stderr line.

## Root cause

`set -m` plus `par_worker "$k" </dev/null &` makes bash call setpgid from both the parent and the child. Under host load the two race and bash prints the warning with `sys_error`, on the script's own stderr. The process group exists either way, so the line is noise, but `--parallel` output is captured with `2>&1` and compared to the serial blocks.

Reproduced standalone (a 3-worker `set -m` spawn loop, 8 `yes` processes as load, `/bin/bash` 3.2): the warning appears in roughly 1 run in 600-1500. The same loop with the fix pattern printed it 0 times in 1500 runs.

## Green run

```
Command: bash tests/test-proof-negctl.sh
Exit: 0
Output:
  test-proof-negctl: all 58 passed
Verdict: PASS
```

```
Command: bash bin/test-affected
Exit: 0
Output:
  test-affected: 25 selected, 25 pass, 0 cached, 0 fail, 0 timeout, 0 uncovered
Verdict: PASS
```

The new case [57] cannot force bash to lose the race, so a `BASH_ENV` stub makes each spawned worker's `export` write the warning plus one real error line to the stderr the warning lands on. It asserts the warning is gone, the three real lines are kept, and the report blocks equal the serial run.

## Negative control

Run on the committed branch with `negctl.sh`, mutating the filter line into a plain `cat` of the spawn stderr:

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-proof-negctl.sh" "perl -pi -e 's/^  grep -v .child setpgid \(. .*$/  cat \"\$par_tmp\/spawn.err\" >&2/' lib/gate/negctl.sh"
Exit: 1 (under mutation, RED expected)
Output:
  test-proof-negctl: 57 passed, 1 FAILED
Restore: git checkout HEAD -- lib/gate/negctl.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The one failure is case [57]. Running the suite against the pre-fix `negctl.sh` fails the same single case: `child setpgid (1 to 1): Operation not permitted` appears in the output.

## Not proven
- The natural race is not forced in the suite; the stub stands in for it. The standalone stress run is the only evidence of the real warning, and it is rare (about 1 in 1000).
- bash 3.2 (`/bin/bash`) reproduced it; bash 5 did not in 600 runs.

## Rollback
Revert the commit; the change is confined to the spawn block of `--parallel`.
