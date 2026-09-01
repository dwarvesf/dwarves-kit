# Proof of done: onboarding-surface revisions (ID-490)

Date: 2026-08-31. Branch: fix/onboarding-surface.

## Green run

| Check | Result | Verdict |
|---|---|---|
| `bash tests/test-meta.sh` after the doc edits | 810/819, failures an exact subset of master's pre-existing set | PASS |
| Gauntlet round 1 on the revised surface (omp/deepseek probe, J1 card) | checker GREEN, K=0, 0 command-not-found, 0 rejected gate writes | PASS |
| Gauntlet round 2 (rule-9 replicate) | checker GREEN, K=0 | PASS |

Full record: `docs/verification/gauntlet/2026-08-31-onboarding-j1-revised/ROUNDS.md` (verdict SOLID).

## Negative control

The pre-revision state IS the red arm, measured twice with independent probes on the same card: `2026-08-31-user-J1` (sonnet, K=4: 10-tool-call jq dead-end, 2 rejected gate-ledger writes, WORKFLOW pointer chase) and `2026-08-31-user-J1-nw` (deepseek, K=4, 3 findings reproduced). Post-revision, the same probe model on the same card hits none of them and demonstrably FOLLOWS the new doc paths (static-jq recipe actions in the transcript, usage discovered via the documented no-args path). Revert the doc edits and the K=4 friction demonstrably returns; the two pre-revision run records are that red state, preserved.
