# Proof of done: Orca mega backend (build scope)

Spec: `docs/specs/SPEC-370-orca-mega-backend.md`. Scope of this proof: all code and stub-based tests, the default-path guarantees, the run lock, the status footer and the rollback verb. Not in scope and not claimed: trial step 0, both trial arms, AC12, AC14 (live Orca; see the PARTIAL table).

## Must-have behaviors and their negative controls

Each control edits the committed file, runs the guarding case (red; a suite timeout counts as red), restores with `git checkout -- <file>`, runs the case again (green). Reproduce with `bash docs/verification/orca-trial/negative-controls.sh [id ...]`. All 27 controls below were red when broken and green after restore (one control, `backoff`, was rewritten after its first run stayed green under load, then re-run red and green).

| Must-have behavior | Guarding case | Control id | Red when broken | Green after restore |
|---|---|---|---|---|
| Default path never loads the backend or calls Orca | AC1 | default-path | yes | yes |
| A worker stopped mid-task reads PARKED exited | AC4 | exited-parks | yes | yes |
| Unverifiable liveness never reads RUNNING | AC5 | unknown-stays-unknown | yes | yes |
| A finished worker with an open box is BLOCKED, never advanced | AC8 | no-self-claim | yes | yes |
| A shipped worker is released after grounded completion | AC6 | grounded-release | yes | yes |
| Only the operator's accept checks a gate sub-goal's box | AC7 | gate-accept-only | yes | yes |
| Rollback stops only live Dispatches | AC9 | rollback-scope | yes | yes |
| Rollback touches only rows whose Task is in this run's map (stub returns foreign rows unfiltered) | AC9 | reset-map-scope | yes | yes |
| A failed stop is never followed by a release | reset-safety | reset-stop-fail | yes | yes |
| Rollback holds the run lock and refuses a live runner | reset-safety | reset-lock | yes | yes |
| Backend value is checked (`claude` or `orca`) | AC10 | backend-allowlist | yes | yes |
| A Delivery is acked only after every message is acted on | AC13 | ack-after-acting | yes | yes |
| `status` never consumes mail | AC13 | status-no-consume | yes | yes |
| A second runner on one dir exits 75 | AC15 | run-lock | yes | yes |
| A recycled pid (live pid, different start time) does not hold the lock | lock-start | lock-start | yes | yes |
| An old Orca fails pre-flight | AC16 | version-preflight | yes | yes |
| Bad `ORCA_*` env values fail pre-flight | env-validate | env-validate | yes | yes |
| The permission mode attestation is required | permission-pin | permission-pin | yes | yes |
| The error wait doubles from a nonzero poll | backoff | backoff | yes | yes |
| A Task with any Dispatch is never started again | AC3 | prior-dispatch | yes | yes |
| A recorded start blocks a restart even when Orca drops stopped rows | start-guard | start-guard | yes | yes |
| BLOCKED is derived before DONE-UNSEEN | rule-order | blocked-first | yes | yes |
| start-outcome-unknown, no-map-row and consumed-but-box-open halt the run | terminal-halts | terminal-halt | yes | yes |
| An INDETERMINATE worker still occupies the wave cap | occupied-unknown | occupied-unknown | yes | yes |
| A started gate! sub-goal blocks every other start | gate-bang | gate-bang-block | yes | yes |
| A rework then retry is gated again (gate keyed by Dispatch) | gate-per-dispatch | gate-per-dispatch | yes | yes |
| The status footer names the oldest unacked message type | footer-type | footer-type | yes | yes |

The suite also carries its own mutation check (case `mutation-check`): it drops the `exited` branch from a temp copy of `orca-backend.sh` and asserts AC4 goes red, so the control cannot rot silently.

## Final runs

| Command | Final line |
|---|---|
| `/bin/bash tests/test-orchestrate-orca.sh` (macOS bash 3.2.57, BSD tools, `bash` on PATH also 3.2) | `Results: 30 passed, 0 failed` |
| same suite, `/opt/homebrew/opt/coreutils/libexec/gnubin` first on `PATH` (GNU tools) | `Results: 30 passed, 0 failed` |
| `/bin/bash tests/test-orchestrate.sh` | `ALL PASS` |
| `/bin/bash tests/test-orchestrate-gate-dispatch.sh` | `ALL PASS` |
| `/bin/bash tests/test-orchestrate-hardening.sh` | `=== 12/12 passed, 0 failed ===` |
| `bash tests/test-meta.sh` | `All meta tests passed.` |
| `bash tests/test-hooks.sh` | `Passed: 719 / 719` |

Every run was one at a time, to completion. Commits under test: `git log --oneline 748358bf..HEAD`.

## PARTIAL (left for the lead)

| Item | Why | Where | Closed by |
|---|---|---|---|
| Trial step 0 (live capture) | creates real Runs visible on the operator's phone | `docs/verification/orca-trial/RUNBOOK.md` (exact commands) | lead |
| Both trial arms | live Orca | spec `## Trial plan` | lead |
| AC12 (trial record values) | needs the arms | `docs/verification/orca-trial/<date>-trial.md` (not yet written) | lead |
| AC14 (capture recorded, stub updated `from live capture`) | needs step 0 | same record; `tests/fixtures/orca-stub/orca` | lead |
| Permission mode is an attestation (`ORCA_PERMISSION_MODE=bypass`), not a probe: no CLI option or read verb exists | `lib/queue/orca-backend.sh` `orca_run`; RUNBOOK check 12 | step 0 |
| Orca row field names | assumptions in stub and backend until step 0 | `docs/implementation-notes/orca-mega-backend.md` item 1 | step 0 |
