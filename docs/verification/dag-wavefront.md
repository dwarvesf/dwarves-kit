# Verification log , SPEC-106 DAG-wavefront scheduling

Per `docs/verification/README.md`: one entry per phase checkpoint + a final/integration run.
Re-run any `Command:` line to regression-check.

## Phase 0 checkpoint , TASK-000 (_run_one_session extraction)

- Task: TASK-000 (zero-behavior-change refactor, unblocks size-dispatch).
- Command: `cd ~/workspace/tieubao/dwarves-kit && bash tests/test-orchestrate.sh`
- Exit: 0
- Output (excerpt): 59 `PASS` lines, ends `---- ALL PASS`. `bash -n lib/orchestrate.sh` exit 0.
- Verdict: PASS (task-verifier 4/4). Commit b5d4d17.
- Re-audit: PASS (recheck-verifier re-executed the suite fresh, 59 PASS, reproduced; extraction confirmed real , fn L342, single call site L458).
- Proof class: inert-ish (refactor); the real proof is the unchanged green suite (negative control deferred to the behavioral tasks that add wave logic).

## Phase 1 checkpoint , TASK-001 (_ready_set) + TASK-002 (mkdir-lock + cmd_flip)

- Tasks: TASK-001 (commit 01544a0), TASK-002 (commit 21cceb0 + stderr fix 73e342c).
- Command: `cd ~/workspace/tieubao/dwarves-kit && bash tests/test-orchestrate-wavefront.sh && bash tests/test-orchestrate.sh`
- Exit: 0
- Output (excerpt): wavefront 29/29 `ALL PASS` (16 ready-set + 13 lock/flip); orchestrate 59/59 `ALL PASS`. `shellcheck -s bash lib/orchestrate.sh` exit 0.
- Verdict: PASS (both task-verifiers 4/4; TASK-002 with adversarial live-holder + 6-way parallel hammer + no-`rm -rf` audit).
- Re-audit: PASS (Phase-1 recheck-verifier re-executed both suites fresh = 29/29 + 59/59; confirmed `_ready_set`/`cmd_flip`/`_lock` DEFINED and DORMANT , cmd_run still uses only `_next`/`_subgoals`, zero wave call sites; no real `rm -rf`; live `cmd_flip` flip works).
- Proof class: behavioral primitives, but NO scheduling wired yet (zero call sites in cmd_run), so byte-identical serial behavior holds (orchestrate suite unchanged). Negative control for the wave BEHAVIOR lands with Phase 2 (TASK-004b) + the final Step-4 control.
- Note: cosmetic stderr leak in the lock pid-read found by the verifier and fixed (73e342c) before checkpoint.

## Phase 2 checkpoint , the wave loop (TASK-003, 004a, 004b, 004c, 005)

- Tasks + commits: TASK-003 `_wave_gate` (b3793bd), TASK-004a `_wave_run` (d028331), TASK-004b size-dispatch wiring (5ebdcfa), TASK-004c convergence sequencer (44f36d8), TASK-005 per-edge HANDOFF (089ea23).
- Command: `cd ~/workspace/tieubao/dwarves-kit && bash tests/test-orchestrate-wavefront.sh && bash tests/test-orchestrate.sh`
- Exit: 0
- Output (excerpt): wavefront 67/67 `ALL PASS`; orchestrate 59/59 `ALL PASS`. `shellcheck -s bash lib/orchestrate.sh` exit 0.
- Verdict: PASS (5 task-verifiers, all 4-6/N). Highlights: the mock-barrier concurrency proof EMPIRICALLY fails serially (verified); byte-identity diff for the wiring is +39/-0 (serial body untouched); the concurrency test caught+fixed a live awk+mv flip race (now flips via the locked CLI); convergence serialization proven by a reversed-id interleave assertion; per-edge HANDOFF keyed on DEPENDENTS (V-CRIT-6 root case passes).
- Re-audit: <pending Phase-2 recheck-verifier>
- Proof class: behavioral. The wave path is REACHABLE + tested at WAVE_CAP>=2 (barrier mock), and DORMANT at default WAVE_CAP=1 (serial byte-identical). Real-wave ACTIVATION (flip-contract prompt injection + real gh merge signature) is deferred to ID-085-followup per Option B. Negative control for the wave behavior = the barrier test (serial impl fails it); the full Step-4 revert-to-RED control lands at completion.


