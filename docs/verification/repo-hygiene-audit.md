# repo-hygiene: recorded runs

Spec: `docs/specs/SPEC-256-repo-hygiene.md`. Run id: `repo-hygiene-audit`. Lane: full.
Full record, including the acceptance comparison against the 2026-09-10 hand pass and the
negative controls: `lib/repohygiene/docs/proof-of-done.md` (co-located with the module, per
SPEC-016). This file is the ship-gate's recorded run and rollback note.

## Recorded runs

| # | Command | Exit | Result |
|---|---|---|---|
| 1 | `bash tests/test-repohygiene.sh` | 0 | 51/51 passed, 0 failed |
| 2 | `bash tests/test-meta.sh` | 0 | Passed: 844 / 844, all meta tests passed |
| 3 | `bash tests/test-kit-contract.sh` | 0 | 25 passed, 0 failed (master baseline: 25/0) |
| 4 | `bash tests/test-audit-scanner-contract.sh` | 0 | all audit-scanner-contract tests passed |
| 5 | `bash tests/run-all.sh` | 1 | 134 suites run, 1 skipped; failures `test-orchestrate-gate-dispatch` (rc=5) and `test-orchestrate-wavefront` (rc=1), both failing identically on master with the same exit codes, neither touching anything this branch changes |

## Live run of the primary flow

The primary flow is the scanner against a real repo. Recorded against `ops-toolkit` in a
detached worktree at the commits that PRECEDE the 2026-09-10 hand-pass fixes, so the decay is
present to find.

```
Command: bash lib/repohygiene/repohygiene.sh scan --repo <ops-toolkit@b2644f33^> --detectors 3,4
Exit:    0
Result:  17 findings. Six detector-3 FIX rows naming tools/vps-mon and tools/alert-triage as
         owners with a destination each, three detector-3 UNSURE rows for central paths with
         competing owners, six closed mega-goals still in the control surface, one detector-4
         FIX for _meta/LAB_LOG.md at 4175 lines against the 2000 the repo's own CLAUDE.md
         states, and one detector-4 UNSURE for a log with no documented budget.

Command: bash lib/repohygiene/repohygiene.sh scan --repo <ops-toolkit@c2e7ae56^> --detectors 1
Exit:    0
Result:  0 findings in 8 seconds at the default 180-day threshold.

Command: bash lib/repohygiene/repohygiene.sh scan --repo <ops-toolkit@c2e7ae56^> --detectors 1 \
           --stale-days 0 --max-candidates 5000
Exit:    0
Result:  93 findings, including _meta/NOTION-TOOLING-MAP.md with its zero-hit reference grep
         quoted inline.

Command: bash lib/repohygiene/repohygiene.sh scan --repo <ops-toolkit> --detectors 5 \
           --cold-mb 20 --cold-days 30
Exit:    0
Result:  8 findings in 2 seconds, every one UNSURE and tagged REPORT ONLY. No deletion
         proposed for any of them.
```

## Negative control

Two invariants broken in turn, each confirmed RED, each restored. Transcript in
`lib/repohygiene/docs/proof-of-done.md` section 4. NC-1 removed detector 3's majority guard
(1 assertion RED). NC-2 changed detector 5's `emit 5 UNSURE` to `emit 5 REMOVE` (2 assertions
RED). `git checkout --` restored both and the suite returned green.

## Rollback

Reverting the branch removes `lib/repohygiene/`, `skills/repo-hygiene/`, and
`tests/test-repohygiene.sh`, and restores one row each in `README.md`, `docs/FEATURES.md`,
`docs/patterns/audit-loop.md`, `agents/audit-scanner.md`, and `_meta/BACKLOG.md`.

There is no runtime state to unwind. The scanner writes nothing outside its own `mktemp -d`,
installs no hook, registers no module, and adds no scheduled job. Nothing in the kit calls it
until an operator invokes the skill. A revert is a plain `git revert` of the branch's commits
with no follow-up step.
