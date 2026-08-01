# Proof of done: doc-count auto-sync in feature-registry.sh

`feature-registry.sh generate` now patches the hand-maintained "N commands / N
agents / ..." count strings in `README.md` and `docs/architecture.md` from the
live file counts, instead of a contributor recomputing and retyping them.
Table ROWS (the one-sentence description per command/agent) still need a
human; only the arithmetic is automated.

## Acceptance criteria

| AC | Claim | Proof |
|---|---|---|
| AC1 | A drift between live files and doc counts fails `tests/test-meta.sh` | negative-control run: 9 RED after adding an uncounted command |
| AC2 | Running `generate` fixes every pure-count assertion without a hand edit | 6 of 9 RED flip to PASS after one `generate` run, no manual edit |
| AC3 | The 3 remaining RED are content gates (a table row), not counts | remaining failures are `table rows`/`summary == command files`, i.e. "needs a row", not a number mismatch |
| AC4 | Restoring to the prior live-file state returns to fully green | `git status --short` shows only the intended 2 files changed after cleanup |
| AC5 | `generate` is idempotent | running it twice back-to-back produces no further diff |

## Confirmation runs

| Run | Command | Result |
|---|---|---|
| pre-edit green | `bash tests/test-meta.sh` | 805/805 |
| negative control | added `commands/zzz-throwaway-test.md` (uncounted), then `bash tests/test-meta.sh` | 9 RED: 6 pure-count mismatches (README layout/header/summary/rows, architecture.md headline x2) + `docs/FEATURES.md` freshness + 2 content-completeness rows |
| auto-heal | `bash lib/registry/feature-registry.sh generate`, then `bash tests/test-meta.sh` | 3 RED remain, all "table rows"/"summary == command files" (needs a written row) -- the 6 pure-count RED + the FEATURES.md freshness RED are gone |
| restored | deleted the throwaway command, `bash lib/registry/feature-registry.sh generate` again, `bash tests/test-meta.sh` | 805/805; `git status --short` shows only `docs/architecture.md` + `lib/registry/feature-registry.sh` changed (the intended diff) |
| idempotency | `generate` run twice back-to-back | second run produces no further diff |

Verdict: PASS (claim: count strings in README.md/architecture.md are now
generator-derived, not hand-maintained; metric: RED-to-PASS transition on the
6 pure-count assertions after one `generate` run with zero manual edits;
threshold: full 805/805 restored, and the NEGATIVE CONTROL proves the
assertions actually detect drift rather than trivially passing).

Command: `bash tests/test-meta.sh`
Exit: 0 (805/805, captured above post-restore)

## Rollback

No schema/deploy/data surface touched (a doc-generator function only). To
revert: `git revert` this commit, or just re-run
`git checkout HEAD~1 -- lib/registry/feature-registry.sh docs/architecture.md`
, the count strings go back to whatever the last hand-edit left them at (no
external state to unwind).

## Reproduce

```
echo '---
description: "throwaway"
---
x' > commands/zzz-throwaway-test.md
bash tests/test-meta.sh                          # expect several RED (count drift)
bash lib/registry/feature-registry.sh generate
bash tests/test-meta.sh                          # expect only "table rows" RED left
rm commands/zzz-throwaway-test.md
bash lib/registry/feature-registry.sh generate
bash tests/test-meta.sh                          # 805/805
```
