# Verification: release-prune-history

Prune the old internal history records from the dwarves-kit tree for a public release, keeping the design record and every file code, tests, hooks, commands, skills and agents read at runtime. A full snapshot of every removed file is the annotated tag `history/2026-10-27` on origin (commit 7fcd43f2).

## File counts per folder

Tracked files under each folder on origin/master and on this branch. "After" includes the files this branch adds (`docs/HISTORY.md` sits outside these folders; the two READMEs, the implementation notes and this proof sit inside them).

| Folder | Before | Removed | After |
|---|---|---|---|
| `docs/verification/` | 1021 | 727 | 294 (295 with this proof) |
| `docs/implementation-notes/` | 260 | 260 | 2 (README, notes) |
| `docs/retro/` | 43 | 43 | 1 (README) |
| `docs/research/` | 61 | 56 | 5 (`foundations/` and the README) |
| `docs/briefs/` | 27 | 24 | 3 (brief template, context, rewrite ledger) |
| `docs/absorption/` | 10 | 8 | 2 (README, TEMPLATE) |
| `docs/audits/` | 3 | 3 | 0 |
| `_meta/megagoals/_archive/` | 330 | 329 | 1 (README) |
| Total | 1755 | 1450 | |

Kept as runtime (file, reader): `docs/verification/task-types.md` (`lib/gate/proof-gate.sh` loads it), `test-design-standard.md` (`commands/test-plan*.md`, two meta tests), `rejected-findings.md` (review agents, `lib/stats`), `COUNTS.md` (`lib/gate/verify-counts.sh`), `done-modes.md` (`tests/test-meta-review-verifiers.sh`), `lanes-as-data/baseline.txt` (`tests/test-lanes-data.sh`), `ceremony-lens/baseline.md` (`lib/stats` anomaly proposal text). Details in `docs/implementation-notes/release-prune-history.md`.

Two sub-folder READMEs were removed with their folders because they described files that no longer exist: `docs/research/2026-08-25-fleet-design/README.md` and `docs/verification/hook-detach-sessionend-demo/README.md`. Both are readable at the tag.

## Green runs
Every removed file exists at the tag (the snapshot is complete):

```
Command: git diff --name-only --diff-filter=D origin/master HEAD | while read p; do git cat-file -e "history/2026-10-27:$p" || echo MISSING $p; done
Exit: 0
Output:
deleted=1450
missing=0
Verdict: PASS
```

Structural meta suite:

```
Command: bash tests/test-meta.sh
Exit: 0
Output:
All hard-claim tests passed.

=== Results ===
Passed: 930 / 930
All meta tests passed.
bash tests/test-meta.sh  7.58s user 12.65s system 4% cpu 7:08.51 total
Verdict: PASS
```

Suites the diff touches (101 named, the rest always-on):

```
Command: bash tests/run-all.sh --changed origin/master --time
Exit: 0
Output:
test-wrap-report-lint                          ok (8s)

run-all: slowest:
  168s test-lanes-data
  111s test-hooks
  92s test-wrap-land
  81s test-flick
  48s test-gate-ledger-check-cache
  47s test-precedent
  47s test-lane-telemetry
  37s test-gate-validate-round
  37s test-ceremony-fits-diff
  30s test-kit-foldin-hooks

run-all: all 103 suites passed, 0 skipped for missing tooling
bash tests/run-all.sh --changed origin/master --time  435.58s user 633.34s system 325% cpu 5:28.47 total
Verdict: PASS
```

Gauntlet tier 1:

```
Command: bash tests/gauntlet/tier1.sh
Exit: 0
Output:
PASS  shellcheck -x tests/gauntlet/*.sh tests/gauntlet/cleanroom/*.sh tests/gauntlet/deploy/gauntlet-campaign

TIER1: GREEN
exit=0
Verdict: PASS
```

Suites outside the `--changed` selection, run alone: doc-figures, gitattributes-union, the lib/stats suites that read the touched adapters. `tests/test-doc-figures.sh` failed its `fz: 1.5` case once when run in parallel with four other suites (the known load flake) and passed 50 of 50 when re-run alone, shown here.

```
Command: bash tests/test-doc-figures.sh
Exit: 0
Output:
  PASS front matter fz scales the PNG too (2344 px for a 780-unit drawing)

doc-figures: 50 passed, 0 failed (50 checks)
Verdict: PASS
```

```
Command: bash tests/test-gitattributes-union.sh
Exit: 0
Output:

  27/27 passed
exit=0
Verdict: PASS
```

```
Command: bash lib/stats/tests/test-review-yield.sh
Exit: 0
Output:

== 39 passed, 0 failed ==
exit=0
Verdict: PASS
```

Generated figures and the feature registry:

```
Command: bash lib/system-design/doc-figures check
Exit: 0
Output:
doc-figures: ok (12 figures)
Verdict: PASS
```

```
Command: bash lib/registry/feature-registry.sh check docs/reference/FEATURES.md
Exit: 0
Output:
feature-registry: docs/reference/FEATURES.md is fresh
Verdict: PASS
```

Dead-reference scan against origin/master (no new dead reference; `comm -13` prints the dead refs present now and absent on master):

```
Command: bash lib/docdrift/refcheck.sh scan --repo .   (diffed against the same scan of an origin/master export)
Exit: 0
Output:
origin/master: SUMMARY | 51 docs | 869 refs checked | 31 dead
this branch:   SUMMARY | 52 docs | 871 refs checked | 29 dead
new dead refs: 0
Verdict: PASS
```

## Negative control

The control targets a file kept as runtime: `docs/verification/done-modes.md`, whose content `tests/test-meta-review-verifiers.sh` greps. Truncating it must turn the suite RED; negctl then restores it.

```
Command: bash tests/test-meta-review-verifiers.sh
Exit: 0 (green before mutation)
Output:
    PASS the re-found-CRITICAL-does-not-quiesce trap is stated (SPEC-112)
    PASS quiescence emits QL-VERDICT round markers (SPEC-112)
    PASS Deferred findings subsection defined (SPEC-112)
    PASS cap divergence pinned: quiescence 3, plain REVISE 2 (SPEC-112 DEC-018)
    PASS over-test coverage-delta row defined (SPEC-112)
    PASS done-modes proof carries the 3 quiescence fixtures + plain-REVISE regression (SPEC-112)
  
  === Results ===
  Passed: 210 / 210
  All meta tests passed.

Mutation: : > docs/verification/done-modes.md
Changed: docs/verification/done-modes.md
Exit: 1 (under mutation, RED expected)
Output:
    PASS the re-found-CRITICAL-does-not-quiesce trap is stated (SPEC-112)
    PASS quiescence emits QL-VERDICT round markers (SPEC-112)
    PASS Deferred findings subsection defined (SPEC-112)
    PASS cap divergence pinned: quiescence 3, plain REVISE 2 (SPEC-112 DEC-018)
    PASS over-test coverage-delta row defined (SPEC-112)
    FAIL done-modes proof carries the 3 quiescence fixtures + plain-REVISE regression (SPEC-112) (expected '0', got '1')
  
  === Results ===
  Passed: 209 / 210
  Failed: 1

Restore: git checkout HEAD -- docs/verification/done-modes.md
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation changed only `docs/verification/done-modes.md` and negctl restored it (`git status` clean after).

## Rollback

Revert the squash commit of this branch to put every removed file back. To restore a single file: `git checkout history/2026-10-27 -- <path>`. To read one without restoring it: `git show history/2026-10-27:<path>`.

## Not proven

- The full `--all` suite was not run (about 25 minutes; a nightly job owns it). Only the `--changed` selection and the named extra suites ran.
- `lib/stats/tests/test-schema-conform.sh` exits 141 on this host both on origin/master and on this branch (it needs a live kit ledger); it is not a result of this change.
- Specs, decisions, the changelog, the board and module-owned proof records under `lib/` still cite removed paths. Those paths resolve at the tag; they were kept whole on purpose.
