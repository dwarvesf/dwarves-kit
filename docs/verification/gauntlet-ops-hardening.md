# Proof of done: gauntlet ops hardening (SPEC-236)

Date: 2026-08-31. Branch: feat/gauntlet-ops-hardening.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/gauntlet/cleanroom/persist-check.sh` | 0 | PASS: `PROBE_CMD='exit 7'` leg persists CARD.md AND run.sh exits 7; `exit 0` leg unchanged. `PERSIST-CHECK: GREEN` |
| `shellcheck -S warning run.sh run-remote.sh watch.sh gauntlet-campaign` | 0 | PASS, clean |
| `watch.sh --last` vs the REAL omp transcript (2026-08-31-user-J1-nw) | 0 | PASS: rendered via the omp filter, non-empty |
| `watch.sh --last` vs the REAL claude transcript (2026-08-31-user-J1) | 0 | PASS: rendered via `pane-tail.jq` (`-> Bash {...}` / `<- result`), post-verifier-fix |
| `bash tests/gauntlet/tier1.sh` | 0 | PASS: TIER1 GREEN with the widened lint glob |
| `bash tests/test-meta.sh` | 1 | PASS for the branch: 810/819, the 9 failures an exact pre-existing subset of master's 10; the 10th (FEATURES freshness) is FIXED here |

## Negative control (revert -> RED -> restore)

The persist fix's red arm is measured, not simulated: pre-branch `run.sh` under `set -e` lost the room on every non-zero probe exit (three evidence-less failures recorded in the 2026-08-31 session trail; the `-nw` run only persisted after hand-patching the probe to exit 0). `persist-check.sh` leg A re-creates that exact condition (`PROBE_CMD='exit 7'`) and now proves persist + exit propagation; reverting the run.sh hunk makes leg A fail (script dies before persist, exit code lost). The watch.sh format gap had its own red measured by the acceptance verifier: pre-fix, the real claude transcript fell to "unrecognized format, plain tail"; post-fix it renders through pane-tail.jq.

## Recorded run

- Command: `bash tests/gauntlet/cleanroom/persist-check.sh`
- Exit: 0
- Output: `PASS leg A (PROBE_CMD='exit 7') (exit=7, CARD.md persisted)` / `PASS leg B (PROBE_CMD='exit 0')` / `PERSIST-CHECK: GREEN`
- Command: `bash tests/gauntlet/tier1.sh`
- Exit: 0
- Output: `TIER1: GREEN`
- Verdict: PASS

## Rollback

Every change is file-scoped and revertible with `git revert` of this branch's squash commit; no migration, no persisted state. The campaign pass-container adopts lazily (first tick after merge); reverting before a new pass starts restores the legacy `campaign-current` real-dir behavior untouched, and after one has started, the dated container keeps its row markers, so re-pointing `campaign-current` back by hand (`ln -sfn <dated-dir> campaign-current`) resumes the old runner cleanly.

## Reproduce

Run the spec's `## Verification` block from the worktree root (docker via colima for persist-check; it SKIPs cleanly without).
