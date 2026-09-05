# tests/run-workflow.sh: the CI step list, run locally

Lane: normal

Runs every `run: bash tests/...` step of `.github/workflows/test.yml` in the workflow's order and prints only the red ones, restoring any tracked file a suite dirtied as a side effect. The 2026-09-05 repair of that workflow scripted this loop four times before it lived here; the battery's acceptance verifier is its other caller.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| fixture workflow, one green + one red step: `RUN_WORKFLOW_FILE=<fixture> bash tests/run-workflow.sh` | 1 | PASS: `RED bash tests/fixture-red.sh (rc=1)` with its FAIL line, `1 red of 2 steps` |
| fixture step that appends to `docs/verification/quiz-gate/sample-quiz.md` | 0 | PASS: `restored 1 side-effect file(s)`, tree clean after |
| the real workflow on this branch: `bash tests/run-workflow.sh` | 0 | PASS: `0 red of 64 steps` once `docs/FEATURES.md` was regenerated (the runner is itself indexed there) |
| `shellcheck -S warning tests/run-workflow.sh` | 0 | PASS |

Recorded run
- Command: `bash tests/run-workflow.sh`
- Exit: 0
- Verdict: PASS

## Parallel run (`-j N`, 2026-09-06)

Every suite builds its own temp dirs, so steps run concurrently; each step's block prints whole, failures are counted through marker files.

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/run-workflow.sh -j 4` on the real list | 0 | PASS, `0 red of 64 steps`, wall 156s |
| `bash tests/run-workflow.sh` (serial, same tree) | 0 | PASS, `0 red of 64 steps`, wall 454s |
| fixture with one red among three, `-j 3` and serial | 1 | PASS, the red step reported in both modes |

## NEGATIVE CONTROL

Targeted edit: blind the runner to step exit codes (`rc=0` after each step).

- Command: `RUN_WORKFLOW_FILE=<fixture> bash tests/run-workflow.sh`
- Exit: 0 with `0 red of 2 steps` while a step failed (RED). Restored from a copy: exit 1, the red step reported.

## Rollback

Delete the file and the README line; the workflow itself is untouched.
