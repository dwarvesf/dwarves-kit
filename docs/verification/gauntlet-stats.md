# Proof of done: gauntlet stats projection (SPEC-240)

`lib/gauntlet/stats.sh` is a read-only projection over the run-record corpus under `docs/verification/gauntlet/`. It prints one convergence table (findings trajectory from QL-VERDICT markers, rounds-to-clean, campaign rows GREEN, probe tokens/cost summed from room transcripts, same-card probe-model deltas) and `--write` drops a dated snapshot. First snapshot committed alongside: `docs/verification/gauntlet/2026-09-01-stats.md`.

## Green run

2026-09-01, live corpus in this worktree (6 record dirs, 5 with ROUNDS files):

```
$ bash lib/gauntlet/stats.sh
| Run | Date | Rounds | Findings | Clean at | Rows GREEN | Probe tokens | Probe cost | Probe |
| 2026-08-06-kit-user | 2026-08-06 | 3 | 3->1->0 | 3 | - | 69703 | 7.2991 | - |
| 2026-08-06-kit-user/J3 | 2026-08-06 | 2 | 0->0 | 1 | - | 76794 | 10.9239 | - |
| 2026-08-31-onboarding-j1-revised | 2026-08-31 | 2 | 0->0 | 1 | - | 172199 | 0.0392 | - |
| 2026-08-31-user-J1 | 2026-08-31 | 1 | 4 | - | - | 13117 | 1.0144 | claude-sonnet-5, headless `claude -p`, one spend |
| 2026-08-31-user-J1-nw | 2026-08-31 | 1 | 4 | - | - | 165557 | 0.0332 | - |
| 2026-09-01-onboarding-campaign | 2026-09-01 | 1 | 2 | - | 10/11 | 1014128 | 0.2214 | omp + deepseek-v4-flash throughout |
```

Result: PASS. Every ROUNDS-bearing record dir appears (the p0-cloud-dispatch dir has no ROUNDS file and correctly does not; `campaign-current` symlink skipped). Both transcript formats parse: omp v3 (`turn_end` with usage under `.message.usage`) and Claude stream-json (`result` event). The deltas table quantifies the flywheel claim: same J1 card, sonnet $1.01 vs deepseek-v4-flash $0.03 at identical K=4 findings.

`--write` behavior: first call wrote the snapshot; an immediate second call refused (`exists; pass --force to overwrite`, exit 1). `git status` after: only the snapshot and the new lib file, zero writes inside record dirs (AC-4).

## Negative control

Scratch copy of `2026-08-31-user-J1` with one marker corrupted to `round=one clean=maybe`:

```
stats.sh: malformed QL-VERDICT in .../ROUNDS.md: `[[QL-VERDICT round=one clean=maybe findings=4]]`
rc=1
```

Restored corpus: green run above. A malformed marker is a loud named error, never a silently skipped row (AC-3).

## Reproduce

```
bash lib/gauntlet/stats.sh            # table on stdout
bash lib/gauntlet/stats.sh --write    # dated snapshot, same-day overwrite refused without --force
```

## Review round

Independent code-reviewer (sonnet, correctness + robustness lens) found 1 HIGH + 2 MEDIUM + 1 LOW; all four fixed and re-verified in the run above:

- HIGH: tokens were per record DIR, so a multi-run dir credited sibling transcripts to the primary row. Now scoped per run by the round-dir convention; the reviewer's independently measured split (69703/$7.30 primary, 76794/$10.92 J3) matches the fixed output exactly.
- MEDIUM: the claude-format jq branch lacked the usage-type guard; one corrupt event could silently blank a whole dir's numbers. Guarded.
- MEDIUM: unquoted `$files` word-splitting; replaced with a bash-3.2-safe indexed array.
- LOW: marker sweep was a substring match; now strict full-line after backtick strip (negative control re-run RED, corpus re-run green).

## Notes

- Repo suite `tests/test-meta.sh`: 815/822; the 7 failures pre-date this branch (verified against origin/master: MANUAL.md lacks devops-triage there too) and are filed as ID-639.
- Findings-graduated-to-Tier1 count (SPEC-240 open question): no greppable marker exists in ROUNDS.md prose yet, so no column ships; it lands when rule-10 graduations get a marker.
