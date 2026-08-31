# Proof of done: gauntlet generalization (SPEC-235)

Date: 2026-08-31. Branch: feat/gauntlet-generalize. Board row: ID-488.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/test-meta.sh` | 1 | PASS for this branch: 810/819, 9 failures, an exact subset of origin/master's 10 (808/818); the 10th master failure, FEATURES freshness, is FIXED here. No new failure. |
| `bash lib/registry/feature-registry.sh generate && git diff --exit-code docs/FEATURES.md` | 0 | PASS, registry fresh |
| `git diff --stat origin/master -- kit.toml docs/specs/SPEC-226-gauntlet-telemetry-learning.md` | 0, empty | PASS, config keys + telemetry contract untouched |
| `git diff --name-only origin/master -- tests/gauntlet` | `cleanroom/run.sh` only | PASS, exactly the one permitted answer-key strip hunk |
| `grep -c gauntlet docs/workflow-paths.md` | 0, output `1` | PASS, the missing projection line added |
| fresh-context acceptance verifier (kit:acceptance-verifier) | - | PASS 4/4 tasks + 3/3 global AC |

## Negative control (revert -> RED -> restore)

- Command: `sed -i '' 's/\[\[QL-VERDICT round=N/[[XX-VERDICT round=N/' commands/gauntlet.md && bash tests/test-meta.sh`
- Exit: 1; Output: `FAIL gauntlet.md lost the QL-VERDICT round marker` (1 matching RED line)
- Restore: `git checkout -- commands/gauntlet.md && bash tests/test-meta.sh`
- Output: `PASS gauntlet.md emits the QL-VERDICT round marker, preset-invariant (SPEC-235)`

## Reproduce

From the worktree root, run the Green-run table's commands verbatim; the spec's `## Verification` section (SPEC-235) is the same list.
