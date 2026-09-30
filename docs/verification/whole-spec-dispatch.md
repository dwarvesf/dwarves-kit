# Verification: whole-spec dispatch (build proof)

Spec: `docs/specs/SPEC-369-whole-spec-dispatch.md`. Branch `feat/whole-spec-dispatch` on origin/master (SPEC-366 to 372 and the rid tag). Rebased onto origin/master a9f0c9dc (config-registry and `sd` fixes merged), then rebuilt after the review round (AMEND-001). Arm A of the A/B run lives in `docs/verification/whole-spec-dispatch-ab.md` and is unchanged. The post-ship sections (`## NEGATIVE CONTROL` trial, dispatch counts, `## A/B`) are not written yet: AC-10, AC-11, AC-12 stay PARTIAL.

## Result per acceptance criterion

| AC | Claim | Verdict | Evidence |
|---|---|---|---|
| AC-1 | execute.md at most 30000 bytes, base 36055 | PASS | 23795 bytes now; `wc -c < commands/execute.md`; base via `git show c5981b0f:commands/execute.md \| wc -c` is 36055 |
| AC-2 | brief labels, grant sentence, `confirmed-by:`, sonnet tier | PASS | `tests/test-whole-spec-dispatch.sh` T2 |
| AC-3 | split closed list, threshold, `PROGRESS: done=` | PASS | same suite, T3 |
| AC-4 | no `Mode C`, `2b-0`, `kit:meta-agent`, `bite-sized`; `agent-for` kept | PASS | same suite, T4; `tests/test-meta-agent.sh` 64/64; `tests/test-kit-contract.sh` C9 wiring lines PASS |
| AC-5 | one end pass, acceptance, integration, `check-edited:`, negative control, `rid=<rid>` | PASS | same suite, T5 |
| AC-6 | sampled recheck wording, script and config | PASS | wording T6 PASS; `recheck-sample.sh` behavior tests PASS (N=0, N=1, determinism, rid key, ledger record, root default, project toml ignored); `execute.recheck_sample` ships 5, honours operator `1`, ignores project toml; `tests/test-config-registry.sh` 59/59 |
| AC-7 | PARTIAL wording | PASS | same suite, T7 |
| AC-8 | docs, ADRs, FEATURES | PASS | grep sweep clean; ADR-0038 exists; supersede notes on 0028 and 0005; `feature-registry.sh check` rc 0 |
| AC-9 | suites | PASS | see suite table |
| AC-10 | negative control trial | PARTIAL | needs the shipped command; the fixture is proven unmeetable (T8 checks below) |
| AC-11 | dispatch hypothesis recorded | PARTIAL | post-ship |
| AC-12 | A/B run | PARTIAL | arm A recorded; arm B post-ship |

## Suites

Command: each `bash tests/<name>.sh` alone, to completion, with a temp `DWARVES_KIT_LOG_DIR`, on the rebased HEAD. Exit is the suite's own.

| Suite | Exit | Final line |
|---|---|---|
| test-meta.sh | 0 | `Passed: 887 / 887` |
| test-hooks.sh | 0 | `All tests passed.` |
| test-meta-agent.sh | 0 | `=== 64/64 passed, 0 failed ===` |
| test-right-arm-parity.sh | 0 | `=== 38/38 passed, 0 failed ===` |
| test-role-classify.sh | 0 | `=== 24/24 passed, 0 failed ===` |
| test-lane-escalation.sh | 0 | `=== 24/24 passed, 0 failed ===` |
| test-outcome-emit-sweep.sh | 0 | `All outcome-emit-sweep tests passed.` |
| test-gate-vocab-recording.sh | 0 | `=== Summary: 20/20 passed ===` |
| test-every-step-review.sh | 0 | `=== 17/17 passed, 0 failed ===` |
| test-spec-task-done.sh | 0 | `spec-task-done green.` |
| test-whole-spec-dispatch.sh | 0 | `=== 37/37 passed, 0 failed ===` |
| test-config-registry.sh | 0 | `=== 59/59 passed ===` |
| test-kit-contract.sh | 0 | `=== kit-contract: 25 passed, 0 failed ===` |
| feature-registry.sh check | 0 | `docs/FEATURES.md is fresh` |

GNU pass with `/opt/homebrew/opt/coreutils/libexec/gnubin` first on PATH: test-whole-spec-dispatch 37/37, test-config-registry 59/59, test-spec-task-done green, test-right-arm-parity 38/38, test-meta-agent 64/64.

## Fixture (T8)

Command: `bash tests/test-whole-spec-dispatch.sh`, fixture section, on a temp copy. Exit 0.

| Check | Result |
|---|---|
| `check.sh unmeetable` on a tree holding `hello.txt` = `hello` | exits 1, prints `AC-3: FAIL` |
| `check.sh meetable` on the same tree | exits 0 |
| `check.sh meetable` with a wrong `hello.txt` | exits 1 (not an always-pass check) |

## Structural negative control (T11)

Command: the same T1 to T7 checks, run inside the suite against `git show c5981b0f:commands/execute.md`. Exit 0 (the suite requires at least 5 red). Result: 7 of 7 red on the base file, 0 of 7 red on the new file. The behavior tests for the two scripts do not depend on the base file.

## Negative controls per must-have

Method per row: the change is committed, a mutation breaks one artifact, the suite goes red, `git checkout -- <file>` restores it, the suite is green again. Script output kept at `/private/tmp/claude-501/wsd/negctl.out`.

| Must-have | Mutation | Red line | After restore |
|---|---|---|---|
| AC-1 size | append 7000 bytes to execute.md | `FAIL T1 execute.md at most 30000 bytes` | 16/16 |
| AC-2 brief | change the grant sentence | `FAIL T2 brief labels, grant, confirmed-by, sonnet tier` | 16/16 |
| AC-3 split | remove `territory-conflict` | `FAIL T3 split closed list, threshold, PROGRESS` | 16/16 |
| AC-4 no persona | add a `2b-0` heading | `FAIL T4 no persona dispatch, agent-for kept` | 16/16 |
| AC-4 meta-agent | add `### Mode C` to meta-agent.md | `FAIL no Mode C in agents/meta-agent.md or commands/execute.md` | 64/64 |
| AC-5 end verification | remove `check-edited:` | `FAIL T5 one end pass, acceptance, integration, check-edit, negative control, rid` | 16/16 |
| AC-6 sampled key | remove `recheck: sampled key=` | `FAIL T6 sampled recheck wording` | 16/16 |
| AC-6 config default | `recheck_sample = 3` in kit.toml | `FAIL execute.recheck_sample ships as 5` | same 57/59 baseline |
| AC-6 root-only table | drop the `execute.recheck_sample` row | AC10 DIFF lists `> execute.recheck_sample` | restored, DIFF lists only `lanes.default` |
| AC-7 PARTIAL | remove `Result: PARTIAL` | `FAIL T7 PARTIAL wording` | 16/16 |
| AC-8 ADR note | remove the supersede note from ADR-0005 | `FAIL: supersede note missing` | `ok passed` |
| AC-8 FEATURES | reword the task-verifier description | `docs/FEATURES.md has DRIFTED` (rc 1) | `is fresh` (rc 0) |
| AC-9 parity | remove `Re-audit: SKIPPED` | `FAIL AC5: execute.md dispatches recheck-verifier on the sampled rule` | 38/38 |
| AC-9 task-done | append `exit 1` to spec-task-done.sh | `FAIL log call exits 0` | green |
| AC-10 fixture | make AC-3 satisfiable (`-eq 4`) | `FAIL check.sh unmeetable exits non-zero` | 16/16 |

## Negative controls for the review fixes

Same method (mutate a committed file, red, `git checkout --`, green; 37/37 after each restore). Output: `/private/tmp/claude-501/wsd/negctl3.out` and `negctl4.out`. Two rows first survived (a wrong sampling key and an ignored root default passed by luck on one rid); the tests now check 16 rids and a rid that N=5 skips, and those rows went red.

| Fix | Mutation | Red line |
|---|---|---|
| 1 slice-boundary verify | `Verify at each slice boundary` removed | `FAIL T5` |
| 1 full lane recheck all | `decide "$RID" 1` replaced by `decide "$RID"` | `FAIL T6` |
| 2 N=0 guard | `-eq 0` changed to `-eq 99` | `FAIL N=0 never samples` |
| 2 key on rid | cksum of `${rid}x` | `FAIL the key is cksum of the rid ... over 16 rids` |
| 2 ledger record | `recheck-x:` | `FAIL the decision is recorded as 'recheck: skipped key=<rid>'` |
| 2 root default | `kit_config_get_root` replaced by `echo 5` | `FAIL no N arg: the root kit.toml default is read` |
| 3 continuation cap | `At most 2 continuations` removed | `FAIL T3` |
| 3 git log check | `git log <base>..HEAD` removed | `FAIL T3` |
| 4 pre-existing test edit | base-existence test replaced by `false` | `FAIL a modified test file that exists at base is flagged` |
| 4 weakened lines | `check-weakened:` renamed | `FAIL added 'cmd || true' ... is flagged check-weakened` |
| 5 LANE-SUGGEST | all occurrences renamed | `FAIL T5` |
| 6 self-attested recheck | `unverifiable` removed | `FAIL T6` |

## Build record

Command: `bash lib/gate/gate-ledger.sh record whole-spec-dispatch build ran "..."`, recorded after the first build. Commit hashes changed with the rebase; `git log origin/master..HEAD` lists them.
