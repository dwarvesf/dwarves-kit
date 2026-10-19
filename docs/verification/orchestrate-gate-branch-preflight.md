# Verification -- orchestrate gate Branch pre-flight

`lib/queue/orchestrate.sh` refuses a `gate` / `gate!` sub-goal whose goal file has no `**Branch:**` header before dispatch. The hold looks the PR up by that branch; the `wave/<id>` fallback never matched the worker's real branch, so the human saw "no PR" while one existed. `auto` sub-goals are unchanged.

## Green run
```
Command: bash tests/test-orchestrate-gate-dispatch.sh
Exit: 0
Output:
PASS B7: gate without **Branch:** is refused pre-flight and not dispatched
PASS B7: the auto sub-goal ahead of it still ran
PASS B7: gate! without **Branch:** is refused pre-flight and not dispatched
PASS B7 (regression pin): gate WITH **Branch:** still dispatches
PASS B7 (regression pin): auto without **Branch:** still dispatches

ALL PASS
Verdict: PASS
```
Also green: `bash tests/test-orchestrate.sh` (ALL PASS) and `bash tests/run-all.sh --changed` (all 39 suites passed).

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-orchestrate-gate-dispatch.sh" "git show HEAD~1:lib/queue/orchestrate.sh > lib/queue/orchestrate.sh"
Exit: 2 (under mutation, RED expected)
Output:
FAIL B7: gate! without Branch not refused (rc=1)
[orchestrate] [guardrail] SG-02 is a gate! sub-goal but opened no PR for its branch; halting (no self-claim, no advance on a dead/incomplete session).
INVOKED SG-02
2 FAILED
Restore: git checkout HEAD -- lib/queue/orchestrate.sh
Exit: 0 (green after restore)
Verdict: PASS
```
The mutation reverts `orchestrate.sh` to its pre-fix revision. Two refusal cases go red (gate and gate!); the old code dispatches the worker and then reports "opened no PR" although the mock `gh` holds a PR for the real branch.

## Not proven
- The wave path (`_wave_run`) never admits gate sub-goals, so it carries no new check and no case.
- `--dry-run` does not preview the refusal.
