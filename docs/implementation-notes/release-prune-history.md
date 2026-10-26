# Implementation notes: release-prune-history

Delta from the task brief, not a mirror of it. The snapshot of every removed file is the annotated tag `history/2026-10-27` (commit 7fcd43f2).

## 2026-10-27 what was decided

**Decision:** remove every file in the eight listed folders except the keep list and the files a script, test or command reads at runtime.

**Why:** the tree ships to the public. Dated working records add noise and cost nothing to restore from the tag.

## Runtime keeps (the reader for each)

| File | Reader |
|---|---|
| `docs/verification/task-types.md` | `lib/gate/proof-gate.sh` loads it as the task-type registry; `lib/classify/task-type-classify.sh` and `commands/assign.md` name it; `test-meta-contract`, `test-meta-docs-registry`, `test-meta-vmodel-dispatch` parse its rows |
| `docs/verification/test-design-standard.md` | `commands/test-plan.md` and `commands/test-plan-review-team.md` tell the agent to apply it; `test-meta-review-verifiers` and `test-meta-vmodel-dispatch` count its section 5b rows |
| `docs/verification/rejected-findings.md` | `agents/advisor.md`, `agents/break-it.md`, `commands/review.md`, `commands/review-team.md` consult it before reporting; `lib/stats` parses it as the review-yield ledger |
| `docs/verification/COUNTS.md` | `lib/gate/verify-counts.sh` rewrites its marked block; `test-meta-docs-registry` pins the block |
| `docs/verification/done-modes.md` | `test-meta-review-verifiers` greps its three quiescence fixtures |
| `docs/verification/lanes-as-data/baseline.txt` | `tests/test-lanes-data.sh` compares lane output against it |
| `docs/verification/ceremony-lens/baseline.md` | the `ledger anomalies` ceremony proposal tells the operator to compare against it (`lib/stats/src/stats/anomalies.py`) |

## Citations rewritten

Comments, "see X" notes and design-record pointers to a removed file now read `history/2026-10-27:<path>`. Specs, decisions, releases, the changelog, the board, module-owned proof records under `lib/` and the rendered bench examples keep their old paths; those resolve at the tag.

## Test changes that are not citation rewrites

- `tests/test-explain.sh`, `tests/test-quiz-gate.sh`, `tests/test-weekend-batch.sh` wrote a committed sample into `docs/verification/` on every run. The samples are gone, so each test now writes its sample to a temp dir. The assertions are unchanged.
- `tests/test-no-personal-paths.sh` dropped its exclusion for the removed `no-personal-paths.md` proof. The scan is stricter, not weaker.

## Folder state after the prune

`docs/retro/` and `docs/implementation-notes/` would have been empty, so each gets a short `README.md`. That keeps the folders in the tree and the links in `docs/README.md` live. Two sub-folder READMEs (`docs/research/2026-08-25-fleet-design/`, `docs/verification/hook-detach-sessionend-demo/`) described files that no longer exist and were removed with their folders.

## Not done

Nothing is pushed or merged. The record of what was removed per folder is in `docs/verification/release-prune-history.md`.
