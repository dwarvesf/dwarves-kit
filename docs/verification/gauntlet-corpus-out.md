# Proof of done: gauntlet bulk artifacts moved to a release asset

## What changed

35 probe `transcript.jsonl` files and 5 `fixture-repo.tar.gz` (40 files, 78,173,886 bytes) left `docs/verification/gauntlet/`. They ship as one asset on release `gauntlet-corpus-2026-10` of `dwarvesf/dwarves-kit` (not latest). `docs/verification/gauntlet/CORPUS.md` holds the tag, asset, sha256, fetch steps and a per-file sha256 and size table. The dir shrank from 76 MB to 1.1 MB. Readers that need a transcript say so when it is absent; readers of `ROUNDS.md` are untouched.

## Gate table

| Claim | Evidence |
|---|---|
| the published asset downloads and matches the sha256 in CORPUS.md | run 1 |
| unpacked files are byte-identical to the removed ones | run 1 |
| `stats.sh` still reproduces the committed token and cost numbers with the corpus unpacked | run 2 |
| `stats.sh` names the gap when the corpus is absent | run 3 |
| every reader and suite is green | runs 4 to 8 |
| the reader check is load-bearing | negative control |

## Run table

Run 1, download from the release into an empty dir, compare to the removed files:

```
Command: gh release download gauntlet-corpus-2026-10 -p gauntlet-corpus-2026-10.tar.gz -R dwarvesf/dwarves-kit && shasum -a 256 gauntlet-corpus-2026-10.tar.gz && tar -xzf ... && cmp (each of 40 files)
Exit: 0
Output:
1539c54d8ec07c00d0a5222857cc4987531ed509df54643efb3f68ce4b87436a  gauntlet-corpus-2026-10.tar.gz
40 files unpacked, 0 cmp differences against the pre-removal files
Verdict: PASS
```

Run 2, corpus unpacked into the tree (git-ignored, `git status` clean), then moved out:

```
Command: bash lib/gauntlet/stats.sh
Exit: 0
Output:
| 2026-08-06-kit-user | 2026-08-06 | 3 | 3->1->0 | 3 | - | 69703 | 7.2991 | - |
| 2026-09-01-onboarding-campaign | 2026-09-01 | 1 | 2 | - | 10/11 | 1014128 | 0.2214 | omp + deepseek-v4-flash throughout |
| 2026-09-01-onboarding-campaign-2 | 2026-09-01 | 1 | 0 | 2 | 11/11 | 916761 | 0.1964 | - |
Verdict: PASS
```

Run 3, corpus absent (the committed state):

```
Command: bash lib/gauntlet/stats.sh
Exit: 0
Output:
stats.sh: note: corpus not unpacked (no transcript.jsonl under docs/verification/gauntlet); probe tokens/cost show '-'. Fetch it per docs/verification/gauntlet/CORPUS.md
> Probe tokens/cost unavailable: corpus not unpacked (see CORPUS.md).
Verdict: PASS
```

Run 4:

```
Command: bash tests/gauntlet/tier1.sh
Exit: 0
Output: (tail, after the test-adopt fix) TIER1: GREEN
Verdict: PASS
```

Run 5:

```
Command: bash tests/test-gauntlet-proof-audit.sh
Exit: 0
Output:
  PASS stats.sh reports an unpacked-corpus gap and still renders
  PASS stats.sh is quiet when a transcript is present
=== 17/17 passed ===
Verdict: PASS
```

Run 6:

```
Command: bash tests/test-adopt.sh
Exit: 0
Output:
PASS=63 FAIL=0
Verdict: PASS
```

Run 7:

```
Command: bash tests/run-all.sh --changed origin/master
Exit: 0
Output:
run-all: all 36 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

Run 8:

```
Command: bash tests/test-meta.sh && bash lib/registry/feature-registry.sh check docs/reference/FEATURES.md
Exit: 0
Output:
Passed: 930 / 930
All meta tests passed.
feature-registry: docs/reference/FEATURES.md is fresh
Verdict: PASS
```

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-gauntlet-proof-audit.sh" "sed -i '' 's/corpus not unpacked/gone/g' lib/gauntlet/stats.sh"
Exit: 0 (green before mutation, 17/17)
Changed: lib/gauntlet/stats.sh
Exit: 1 (under mutation, RED expected)
Output:
  FAIL stats.sh reports an unpacked-corpus gap and still renders
  === 16/17 passed ===
Restore: git checkout HEAD -- lib/gauntlet/stats.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Rollback

Revert the commit `chore(gauntlet): move bulk run artifacts to a release asset`. The files return to the tree from history and `CORPUS.md`, the `.gitignore` rule and the reader changes go away together. The release asset stays; it is inert without `CORPUS.md`.
