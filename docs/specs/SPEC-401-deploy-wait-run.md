# Spec: wrap deploy-wait run mode
Generated: 2026-10-09
Status: DRAFT
Lane: full
Depth: standard (both gh calls were sampled live and the poll loop already exists in wrap-deploy.sh)

## Problem
`wrap deploy-wait` only waits on check runs, which fits a push deploy. A dispatch deploy (`gh workflow run`) records a workflow run, not a check run on the merge commit, and has no wait verb. In one session the lead hand-polled `gh run view` in a for-loop four times, and `gh run watch` died once on a transient network timeout. `commands/wrap.md` step 4 forbids polling by hand, yet its dispatch bullet gives no verb to use instead.

## Terms
none

## Solution

### Approaches considered
1. Run mode inside `cmd_deploy_wait` (`--run <id>` or `--workflow <file>`): reuses arg parsing, validation, the timeout clock, and the transient classifier. Tradeoff: the function grows a second poll loop.
2. A new verb `deploy-wait-run`: clean separation. Tradeoff: a second front door for one concept, and the arg validation gets copied.
3. Document `gh run watch --exit-status` in wrap.md: no code. Tradeoff: it died on a transient timeout, and it never checks headSha.

### Chosen approach + why
Approach 1. The operator already knows `deploy-wait <owner>/<name> <sha>`; run mode adds a source of truth for the same question ("is `<sha>` deployed?") and keeps one verb, one grammar, one exit-code table. The poll body goes in a new function `_deploy_wait_run_poll` in `lib/wrap/wrap-deploy.sh`, so check mode stays untouched.

### Extensibility & boundaries
- Load-bearing dimension: the number of ways to name a run. Today two (`--run <id>`, `--workflow <file>`); a third (a `--ref` filter) would be one more resolver step in the same function.
- `--ref` is NOT added. The positional `<sha>` is a stronger filter than a ref, and `gh run list --commit <sha>` accepts it (sampled below).
- Units: arg parse (existing), run resolver (new, 1 `gh run list` call), run poll (new, 1 `gh run view` call per tick). Each is testable alone through the `gh` stub.

## Picture
```
wrap deploy-wait o/r SHA --check X        wrap deploy-wait o/r SHA --run ID | --workflow F
        |                                         |
  check-runs API poll (existing)           resolve run id (--workflow only):
        |                                    gh run list --workflow F --commit SHA
        |                                         |
        |                                  gh run view ID --json status,conclusion,headSha
        |                                         |  (transient error: retry, bounded)
        v                                         v
  DEPLOYED / FAILED / TIMEOUT / ERROR      DEPLOYED / FAILED / TIMEOUT / ERROR
      (0 / 1 / 124 / 2)                          (0 / 1 / 124 / 2)
```

## Design
obvious: one new poll loop that mirrors the existing check-mode loop and reuses its helpers; no schema, no new component, no irreversible choice.

## Technical Design

### Interfaces (I/O contract)
Usage: `wrap deploy-wait <owner>/<name> <sha> --run <run-id> [--timeout <secs>]` or `... --workflow <file> [--timeout <secs>]`.
- `--run`, `--workflow` and `--check` are mutually exclusive; two of them is exit 64. `--run` takes digits only. `--workflow` takes a file name or id matching `^[A-Za-z0-9_.-]+$` (no slash, no leading `-`).
- Reads only: `gh run view <id> -R <slug> --json status,conclusion,headSha`, and for `--workflow` also `gh run list -R <slug> --workflow <file> --commit <sha> --limit 1 --json databaseId`. It dispatches nothing.
- `--workflow` polls the list until a run for the sha appears (a dispatch can lag a few seconds), takes the highest `databaseId`, then polls that run. An empty list is "not yet", not an error.
- Pass condition: `status == completed` AND `conclusion == success` AND `headSha` starts with the given sha (case-insensitive prefix, given sha 7 to 40 hex). The comparison runs on every completed read.

Output grammar, same as check mode (one conclusion line, then one terminal line):
| Case | stdout | exit |
|---|---|---|
| success, sha matches | `success run <id>` then `DEPLOYED <sha7>: run <id> succeeded` | 0 |
| completed, conclusion not success | `<conclusion> run <id>` then `FAILED <sha7>: run <id> <conclusion>` | 1 |
| completed success, headSha differs | `success run <id>` then `FAILED <sha7>: run <id> headSha <got7> != <sha7>` | 1 |
| timeout (`--timeout`, default 600) | `TIMEOUT <sha7> after <N>s: run <id> <status>` (`no run for the sha yet` when unresolved) | 124 |
| gh missing or unauthenticated, non-transient read error, unreadable JSON, transient cap hit | `ERROR <sha7>: <why>` | 2 |
| usage | usage line on stderr | 64 |

- Transient errors reuse `_gh_merge_transient`. A transient read prints `deploy-wait <sha7>: transient read error, retrying: <err>` on stderr and polls again. `DEPLOY_WAIT_RUN_RETRY_MAX` (default 5) caps CONSECUTIVE transient errors; one good read resets the count; hitting the cap is exit 2 with `ERROR <sha7>: <n> consecutive transient read errors: <err>`. This is the bound `gh run watch` lacked.
- Reuses `DEPLOY_POLL_SECS`, `_dw_seconds` and the wall-clock timeout fold from check mode.
- Invariants: no write to the repo or to GitHub; the temp error file is removed on exit, as in check mode; check mode behavior and its tests are unchanged.

### Data model changes
none
### API changes (endpoints, request/response shapes)
none beyond the CLI above.
### UI changes (screens, components, interactions)
none
### Infrastructure changes
none

## Task Breakdown
Each task is atomic.

### Phase 1: Core
- [ ] TASK-A: Parse `--run` and `--workflow` in `cmd_deploy_wait` with the exclusivity and charset rules; route to `_deploy_wait_run_poll`. Accept: each bad combination in the table exits 64 with the usage line (test).
- [ ] TASK-B: Implement `_deploy_wait_run_poll` (resolve, poll, headSha prefix check, transient cap, timeout, exit table). Accept: every row of the output table has a test case on the `gh` stub.

### Phase 2: Docs
- [ ] TASK-C: Update `commands/wrap.md` step 4: the Dispatch deploy bullet names `bin/wrap deploy-wait <owner>/<name> <merge-sha> --run <id>` (or `--workflow <file>`) in place of "dispatch it and confirm headSha"; line 143 ("`deploy-wait` dispatches nothing; it only reads check runs") now says "check runs or one workflow run". Accept: `grep -n "\-\-run" commands/wrap.md` hits the bullet; the existing no-poll-by-hand rule also names `gh run view` loops.
- [ ] TASK-D: Extend the `deploy-wait` usage comment block and `--help` text in `lib/wrap/wrap-deploy.sh` and any CLI usage string in `lib/wrap/wrap.sh`. Accept: `bin/wrap deploy-wait` with no args prints the new usage.

## After state
- [ ] `bin/wrap deploy-wait o/r <sha> --run <id>` exits 0 and prints `DEPLOYED` only for a completed, successful run whose headSha matches. (Today: the verb has no run mode and exits 64 on `--run`.)
- [ ] A transient `gh` failure mid-wait does not end the wait, and `DEPLOY_WAIT_RUN_RETRY_MAX` consecutive ones exit 2. (Today: the lead's `gh run watch` died on one.)
- [ ] `commands/wrap.md` step 4's dispatch bullet names the verb. (Today: it names none.)
- [ ] `bash tests/test-wrap-deploy.sh` passes, the new cases included.

## Quality requirements
none

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] Tests cover the happy path and the edge cases below
- [ ] Check-mode cases in `tests/test-wrap-deploy.sh` pass unchanged

## Verification
`bash tests/test-wrap-deploy.sh && bash tests/run-all.sh --changed origin/master`
Negative control: see Grounding.

## Edge Cases
1. Run completed `success` on a different sha (a re-dispatch of an older commit): exit 1, `headSha` mismatch line, never DEPLOYED.
2. `--workflow` finds no run yet: keep polling; at timeout, exit 124 with `no run for the sha yet`.
3. `--workflow` finds two runs for the sha (a re-dispatch): the highest `databaseId` wins.
4. Run `completed` with `conclusion` `cancelled`, `skipped`, `failure` or `timed_out`: exit 1 naming the conclusion. A skipped deploy deployed nothing.
5. Run `queued` or `in_progress` with `conclusion` null or empty: not completed; keep polling, print `run <id> <status>` on stderr.
6. Transient error then a good read: the retry count resets.
7. Non-transient error (HTTP 404 for a wrong run id): exit 2 at once with the first stderr line.
8. Given sha is 7 hex, headSha is 40 hex: prefix match passes; given sha longer than headSha or non-matching never passes.
9. `--run 0abc` (non-digits) or `--run` with `--check`: exit 64.
10. JSON that is not an object with the three keys: exit 2 `unreadable run answer`.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Network blip on gh | stderr matches `_gh_merge_transient` | bounded retry, then exit 2 (unverified, never DEPLOYED) |
| Caller kills the wait at its tool limit | no terminal line | wrap.md already says to run it in the background or pass `--timeout` under the limit |
| Wrong run id or repo | HTTP 404 | exit 2 with the gh error |
| Run for a different commit reported green | headSha prefix compare | exit 1 FAILED headSha mismatch |
| New transient wording not in the classifier | exit 2 on a real blip | operator reruns; the classifier is shared with `_gh_merge_retry`, one fix covers both |

## Out of Scope
- Dispatching the deploy: `deploy-wait` only reads (wrap.md Out of Scope).
- A `--ref` filter: the sha is the filter.
- Following reruns of the same run id: a rerun keeps the id and updates the same record, so the poll sees it.
- Changing check-mode behavior.

## Touches
- lib/wrap/**
- tests/test-wrap-deploy.sh
- commands/wrap.md

## Decision Log
- DEC-A: one verb with a run mode, not a new verb. One grammar and one front door beat a copied validator. Rejected: `deploy-wait-run`, `gh run watch` in docs.
- DEC-B: headSha mismatch is exit 1, not 2. The read worked; the deploy is not the one asked about, which is a failed verification. Rejected: exit 2.
- DEC-C: no `--ref`; `gh run list --commit` already filters by sha. Rejected: ref filter plus a sha check.
- DEC-D: transient retries capped by consecutive count, plus the timeout. Check mode retries until timeout only; a run poll with a 600s default would otherwise hide 60 straight failures.

## Open questions
(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)

## Grounding
Live samples, 2026-10-09, read-only, repo `dwarvesf/foundation-workers`, default branch `main`.

`gh run view 37923037389 -R dwarvesf/foundation-workers --json status,conclusion,headSha`:
```
{"conclusion":"success","headSha":"22ae8a6ceb8d69bcf942b70d7eedd67336d990a9","status":"completed"}
```
Keys are exactly `status`, `conclusion`, `headSha`; `headSha` is the full 40-hex sha, so a 7-hex given sha needs a prefix compare. A `queued` or `in_progress` run's `conclusion` is not sampled here (no live run was available); the code treats null and the empty string alike as "not completed", and the first test case pins both.

`gh run list -R dwarvesf/foundation-workers --workflow deploy.yml --commit 22ae8a6ceb8d69bcf942b70d7eedd67336d990a9 --limit 1 --json databaseId,status,conclusion,headSha`:
```
[{"conclusion":"success","databaseId":37923037389,"headSha":"22ae8a6ceb8d69bcf942b70d7eedd67336d990a9","status":"completed"}]
```
`--commit` is accepted by `gh run list`, and the id field is `databaseId`. The workflow named "Deploy" exists (`gh workflow list` shows `Deploy active 318394381`); the file name `deploy.yml` resolved.

Negative control (dry trace). Mutation: in `_deploy_wait_run_poll`, delete the headSha prefix test so success alone returns 0.
- Fixture: the `gh` stub in `tests/test-wrap-deploy.sh` serves `run view` JSON `{"status":"completed","conclusion":"success","headSha":"ffffffffffffffffffffffffffffffffffffffff"}` while the call passes `SHA=0123456789abcdef0123456789abcdef01234567`.
- Path: poll reads the fixture, `status == completed`, `conclusion == success`; with the compare removed the function prints `DEPLOYED 0123456: run <id> succeeded` and returns 0.
- Red test: `run mode: success on a different headSha exits 1` expects rc 1 and `FAILED 0123456: run <id> headSha fffffff != 0123456`, so it fails (rc 0, DEPLOYED printed) under the mutation and passes without it. A second assertion, `chk_no ... DEPLOYED`, also goes red.

Second control, for the retry cap. Mutation: remove the consecutive counter. Fixture: `read-1..read-9.rc` all 1 with stderr `HTTP 502`. Path: the loop never reaches exit 2 and ends at the timeout with 124. Red test: `run mode: 5 consecutive transient errors exit 2` expects rc 2, so it fails with 124.
