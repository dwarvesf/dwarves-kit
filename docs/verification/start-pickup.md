# Proof of done: start-pickup
Profile: feature   Proof class: behavioral

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | `handoffs.sh list` tags each handoff file LIVE / DEAD / UNCITED by checking its cited board IDs against the board on origin | PASS | R1 |
| 2 | Closed means the Status keyword is shipped, dropped, done, or resolved | PASS | R1 |
| 3 | No origin remote falls back to the working tree, tagged `(local)` | PASS | R1 |
| 4 | `/kit:start`'s Full report gains a Pick up section deriving buckets from the board and handoffs, ending in one recommended next action | PASS | R2 (inert, docs) |
| 5 | The board-owns-the-work / handoff-owns-the-context rule, plus the pre-mint origin+PR check, is stated in the command | PASS | R2 |
| 6 | Negative control: reverting the liveness logic turns the test suite red | PASS | R3 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | `lib/session/handoffs.sh`: `_load_board`, `_origin_default_branch`, `_row_status`, `_status_is_closed`, `handoff_liveness`; wired into `cmd_list`'s per-file loop. `commands/start.md`: new `2c. Pick up` block in the `--full` report. |
| Where | `lib/session/handoffs.sh`, `lib/session/tests/test-handoffs.sh`, `commands/start.md` |
| How it runs | `bash lib/session/handoffs.sh list [--repo DIR] [--days N]`, called by `/kit:start --full`. Liveness fetches `origin` once per invocation, reads `_meta/BACKLOG.md` + `_meta/BACKLOG-archive.md` off `origin/<default-branch>` via `git show`, falls back to the working tree when there is no origin. |
| Reversibility | Read-only tool; `git revert` on the two commits fully restores prior behavior. No state, no migration. |

## 3. Confirmation (runs)

| Run | When (ISO+tz) | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-09-18T08:12+07:00 | `bash lib/session/tests/test-handoffs.sh` | 0 | PASS (14/14, incl. the git-fixture LIVE/DEAD/UNCITED/local cases) |
| R2 | 2026-09-18T08:20+07:00 | `bash tests/run-all.sh --changed` | 0 | PASS (7/7 suites; docs-only change has no executable check of its own, inert) |
| R3 | 2026-09-18T08:24+07:00 | `bash lib/gate/negctl.sh "$(pwd)" "bash lib/session/tests/test-handoffs.sh" "git checkout HEAD~1 -- lib/session/handoffs.sh"` | 0 | PASS (green -> RED under mutation -> restored green) |

## 4. Run detail

### R1 GREEN
Command: `bash lib/session/tests/test-handoffs.sh`
Exit: 0
Output (excerpt):
```
[10] DEAD: all cited rows closed on origin (local copy says the opposite)
  ok: dead-one.md verdict: 3d  _meta/handoffs/dead-one.md  next: Nothing left, ID-100 shipped.  DEAD (all 1 cited rows closed, delete it)
[11] LIVE: cited row open on origin (local copy says the opposite)
  ok: live-one.md verdict: 2d  _meta/handoffs/live-one.md  next: Finish ID-200.  LIVE (1 open: ID-200)
[12] UNCITED: no board IDs in the file
  ok: no-ids.md verdict: 1d  _meta/handoffs/no-ids.md  next: Just a reminder, nothing tracked.  UNCITED (no row IDs; read it)
[13] local fallback: no origin, unresolved id stays open, tagged (local)
  ok: local fallback marker: 4d  _meta/handoffs/local-fallback.md  next: Still need ID-999, and this repo has no git remote.  LIVE (1 open: ID-999) (local)
smoke: all 14 passed
```
Verdict: PASS

### R2 GREEN (repo-wide changed-suite gate)
Command: `bash tests/run-all.sh --changed`
Exit: 0
Output (excerpt):
```
run-all: 7 suites, 4 at a time, 0 serial
test-boundary-lint                             ok
test-config-registry                           ok
test-kit-contract                              ok
test-meta                                      ok
test-no-personal-paths                         ok
test-no-scattered-ids                          ok
test-registry-freshness-guard                  ok
run-all: all 7 suites passed, 0 skipped for missing tooling
```
Verdict: PASS

### R3 NEGATIVE CONTROL
Command: `bash lib/gate/negctl.sh "$(pwd)" "bash lib/session/tests/test-handoffs.sh" "git checkout HEAD~1 -- lib/session/handoffs.sh"`
Exit: 0
Output (excerpt):
```
## Negative control (negctl)
Command: bash lib/session/tests/test-handoffs.sh
Exit: 0 (green before mutation)
Mutation: git checkout HEAD~1 -- lib/session/handoffs.sh
Changed: lib/session/handoffs.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/session/handoffs.sh
Exit: 0 (green after restore)
Verdict: PASS
```
Verdict: PASS

### ROLLBACK/RESTORE
`git checkout HEAD -- lib/session/handoffs.sh` (run by negctl itself, confirmed green after). No deployed state to roll back; a plain `git revert` undoes both commits.

## 5. Reproduce

```
bash lib/session/tests/test-handoffs.sh
bash tests/run-all.sh --changed
bash lib/gate/negctl.sh "$(pwd)" "bash lib/session/tests/test-handoffs.sh" "git checkout HEAD~1 -- lib/session/handoffs.sh"
```
