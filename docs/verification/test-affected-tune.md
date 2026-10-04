# Proof of done: test-affected tune

Branch `perf/test-affected-tune`, three commits on master 202b00af. Spec: `docs/specs/SPEC-390-test-affected-tune.md`. Notes: `docs/implementation-notes/test-affected-tune.md`.

Verdict summary: mapping and replay hold (zero misses over 49 merged PRs), negative control recorded, TIMEOUT line and shared data file work. One honest gap: the back-to-back run check did not come out clean (see "Back-to-back runs"). The host was shared and heavily loaded the whole time (load average 3 to 240).

## Unit suites on the final head

```
Command: bash tests/test-test-affected.sh
Exit: 0
Output: test-test-affected: 58 passed, 0 failed
Verdict: PASS
```

```
Command: bash tests/test-run-all-timeout.sh
Exit: 0
Output: test-run-all-timeout: all 8 passed
Verdict: PASS
```

Also green earlier in the build: `test-run-all-changed` (all 12), `test-run-all-time` (all 4), `test-suite-knob` (7/7), `test-bin-forwarders` (48, after naming the new data file in the bin census). `docs/FEATURES.md` regenerated with `lib/registry/feature-registry.sh generate`.

## Timeout measurement (D4, R10)

```
Command: KIT_RUN_ALL=1 RUN_ALL_TIMEOUT_SECS=1200 bash tests/run-all.sh --all --time    (x3, clone of 202b00af)
Exit: 0, 0, 0 (every one of 206 suites ok in each run); a fourth run was stopped for time, a fifth never started
Output: load average (1 min) at the start of runs 1, 2, 3: 3.05, 26.05, 228.46
        slowest in run 3: test-lanes-data 346s, test-meta-docs-registry 341s, test-hooks 330s, test-orchestrate-orca 286s
Verdict: PASS (samples collected); p95 of 3 samples = the max (R10)
```

`bin/test-affected.timeouts` holds one line per suite, 206 suites, `max(60, 2 x p95)`. Top 15 by limit:

| Suite | Samples (s) | p95 | Limit (s) |
|---|---|---|---|
| test-lanes-data | 115, 346, 157 | 346 | 692 |
| test-meta-docs-registry | 246, 341, 272 | 341 | 682 |
| test-hooks | 149, 330, 190 | 330 | 660 |
| test-wrap-land | 76, 1, 1 | 76 | 600 (hand-set, see below) |
| test-orchestrate-orca | 190, 286, 227 | 286 | 572 |
| test-config-seams | 136, 199, 198 | 199 | 398 |
| test-wrap-adopt | 99, 191, 94 | 191 | 382 |
| test-flick | 89, 154, 105 | 154 | 308 |
| test-precedent | 57, 143, 85 | 143 | 286 |
| test-orchestrate | 66, 128, 66 | 128 | 256 |
| test-gate-validate-round | 41, 126, 70 | 126 | 252 |
| test-wrap-merge | 76, 125, 88 | 125 | 250 |
| test-board-work | 71, 119, 62 | 119 | 238 |
| test-wrap-apply | 118, 96, 58 | 118 | 236 |
| test-wrap-ci | 24, 93, 47 | 93 | 186 |

169 of the 206 suites sit at the 60 s floor. `tests/run-all.sh` reads the same file (its hardcoded `test-meta*) echo 900` arm is gone).

## Replay: last 10 merged PRs, before vs after

```
Command: python3 replay.py <scratch> <master bin/test-affected> <tuned bin/test-affected> <PR numbers> out.json   (--list only, no suite runs)
Exit: 0
Output: 49 PRs replayed, PRs with a missed area suite: 0
Verdict: PASS
```

Each PR's changed paths are re-created as a commit on the post-split tree (so the area suites exist), then `bin/test-affected --base 202b00af --list` runs with master's script (before) and the tuned script (after). "Run-all set" is what `tests/run-all.sh --changed` would run: the runner expanded to its eight area suites, plus the `# always:` suites. "Area suites the PR reads" is computed apart from `meta_areas`: the replay scans each area suite's non-comment lines for the path, a long basename of a source file, or a glob (`commands/*.md`, `git ls-files '*.md'`, `ls docs/specs/`) the path falls under, honouring the exclusion lists beside each scan.

| PR | files | before (listed / run-all set) | after (listed / run-all set) | area suites the PR reads | area suites in the after set | missed |
|---|---|---|---|---|---|---|
| #909 | 17 | 20 / 24 | 20 / 24 | all eight (the PR edits them) | 8 | 0 |
| #908 | 6 | 11 / 22 | 12 / 17 | docs-registry, plugin-hooks, vmodel-dispatch | 3 | 0 |
| #907 | 26 | 29 / 38 | 32 / 36 | agents-commands, docs-registry, plugin-hooks, review-verifiers, spec-depth, vmodel-dispatch | 6 | 0 |
| #906 | 10 | 31 / 40 | 32 / 40 | docs-registry, goal-ledger, plugin-hooks, spec-depth, vmodel-dispatch | 8 | 0 |
| #905 | 1 | 27 / 36 | 26 / 31 | plugin-hooks, spec-depth, vmodel-dispatch | 3 | 0 |
| #904 | 4 | 9 / 20 | 10 / 15 | docs-registry, plugin-hooks, vmodel-dispatch | 3 | 0 |
| #903 | 2 | 10 / 21 | 11 / 16 | docs-registry, plugin-hooks, vmodel-dispatch | 3 | 0 |
| #902 | 1 | 2 / 14 | 2 / 7 | plugin-hooks | 1 | 0 |
| #901 | 1 | 6 / 16 | 6 / 10 | plugin-hooks, vmodel-dispatch | 2 | 0 |
| #900 | 1 | 22 / 29 | 23 / 28 | agents-commands, contract, docs-registry, plugin-hooks, review-verifiers, spec-depth, vmodel-dispatch | 7 | 0 |
| total | | | 260 before, 224 after | | | 0 |

"Listed" is higher after than before in places because `--list` now names each area suite where it used to name the runner once; the run-all set is the comparable number. Over all 49 PRs merged 2026-10-01 to 04: 1593 suites before, 1418 after, zero PRs with a missed area suite. Two real gaps were found and fixed by this check during the build: `vmodel-dispatch` counts `hooks/*.sh` and `skills/*/SKILL.md` against the README tables, and a markdown file under `lib/` is read by the `*.md` scan.

## The branch that picked about 41 suites

No merged PR from 2026-10-01 to 04 reproduces exactly 41. Master's script on each PR's own tree gives 42 listed on #864 (flick contract skeleton) and #890, and 39 on #895. Before vs after on the post-split tree for the closest candidates, plus the largest PR of the last ten:

| PR | files | before (listed / run-all set) | after (listed / run-all set) | area suites before / after | missed |
|---|---|---|---|---|---|
| #864 feat(decide): add the flick contract skeleton | 14 | 54 / 61 | 56 / 59 | 8 / 6 | 0 |
| #866 feat(flick): add word gate on wrap-7b slugs | 9 | 52 / 59 | 54 / 57 | 8 / 6 | 0 |
| #890 fix(battery): refuse a small change | 8 | 51 / 57 | 53 / 57 | 8 / 8 | 0 |
| #895 feat(flick): add clef backend | 8 | 44 / 52 | 44 / 47 | 8 / 3 | 0 |
| #907 feat(wrap): adopt verb (largest of the last 10) | 26 | 29 / 38 | 32 / 36 | 8 / 6 | 0 |

After is fewer in each case but the saving is bounded: the tuning only trims the eight area suites, and most of a large diff's picks come from the reference scan (basename mentions), which this change does not touch.

## Back-to-back runs of the selected suites

```
Command: bash bin/test-affected --no-cache --base 202b00af    (x3, branch head, 15 suites selected, run sequentially)
Exit: 1, 1, 0
Output: run 1 (load 13.9): TIMEOUT tests/test-wrap-land.sh (limit 152s); 14 pass, 1 timeout       wall 653s
        run 2 (load 37.3): FAIL tests/test-meta-docs-registry.sh, Passed 119 / 120; 14 pass, 1 fail   wall 661s
        run 3 (load 42.6): 15 selected, 15 pass, 0 cached, 0 fail, 0 timeout                          wall 953s
Verdict: PARTIAL. The check did not come out clean, for two different reasons below.
```

- **Run 1, false TIMEOUT, fixed.** `test-wrap-land` caches passed sections and keys the cache on every file under `lib/`, `bin/` and `tests/lib/`, so adding `bin/test-affected.timeouts` made run 1 a cold run. The three measurement samples were one cold run (76 s) and two warm ones (1 s), so 2 x p95 undercounted the cold case. The line is now hand-set to 600 s and the data file header says why. The suite was not re-run after the change (stopped for time, R13), so the fix is reasoned, not re-measured.
- **Run 2, a FAIL, not a TIMEOUT, not explained.** `test-meta-docs-registry` lost one assertion in this run only. Run alone on the same head it passed: `bash tests/test-meta-docs-registry.sh` exit 0, `Passed: 120 / 120`. Another worker was running the same suites concurrently against the same host during that window, which is the likely cause, but I did not reproduce or confirm it.
- **Run 3 clean.** Every suite passed, no TIMEOUT.

## Negative control

The mapping was committed first (`a7bde1e8`), then broken in the worktree's `bin/test-affected` and restored with `command cp -f` from a saved copy. Fixture: the replay tree for #886, which changes `hooks/harvest.sh`.

```
Command: bash bin/test-affected --base 202b00af --list     (replay tree for #886, tuned script, arm intact)
Exit: 0
Output: tests/test-meta-vmodel-dispatch.sh  (reads hooks/harvest.sh)
Verdict: PASS (area X = vmodel-dispatch is picked)
```

```
Command: cp bin/test-affected <saved>; delete the line `hooks/*) echo "plugin-hooks vmodel-dispatch docs-registry" ;;`; bash bin/test-affected --base 202b00af --list
Exit: 0
Output: tests/test-meta.sh  (reads hooks/harvest.sh (no area attributed))
Verdict: PASS (fail-safe: an unmapped meta input falls back to the runner, which run-all expands to every area, so deleting a whole arm cannot lose coverage)
```

```
Command: edit the same arm to drop vmodel-dispatch ("plugin-hooks docs-registry"); bash bin/test-affected --base 202b00af --list; python3 replay.py <scratch> <master script> <edited script> 886 out.json
Exit: 0 (--list); replay out.json: missing = ['vmodel-dispatch']
Output: no tests/test-meta-vmodel-dispatch.sh line in the list
        PR 886 missed area suites: ['vmodel-dispatch']  (scan hooks/*.sh <- hooks/harvest.sh)
Verdict: PASS (X not picked, the replay reports the miss)
```

```
Command: command cp -f <saved> bin/test-affected; git diff --quiet bin/test-affected; bash bin/test-affected --base 202b00af --list; python3 replay.py ... 886 out.json
Exit: 0
Output: tests/test-meta-vmodel-dispatch.sh  (reads hooks/harvest.sh)
        PR 886 missed area suites: []
Verdict: PASS (restored, picked again; `git status` clean for bin/)
```

## Not proven

- A re-run of `test-wrap-land` cold under the 600 s line, and a clean 3-run streak after that fix.
- The cause of the run 2 `test-meta-docs-registry` FAIL.
- The limits are 2 x p95 from three samples on a host at load up to 228, so they are generous upper bounds, not tight ones. Five samples at normal load were not collected.
- The replay driver and raw timings live in the run's scratch directory and are not committed; the replay builds synthetic commits (a path deleted by a PR and gone from the tree is modelled as an added stub), and its "area suites the PR reads" scan is a second implementation, not an execution trace.
- A path in a dated archive dir (`docs/verification/` and similar) now picks no area suite by design; only a direct mention picks one.
