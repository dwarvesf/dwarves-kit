# Proof of done: repo layout

## What changed

Mechanical layout refactor with no behavior change. Reference docs moved to `docs/reference/`, rule and guide templates to `templates/`, the Hermes adapter to `integrations/hermes/`, `docs/CHANGELOG.md` to the root, and four strays into their record folders. Every living reference was repointed. Dated records keep their old citations. Delta decisions: `docs/implementation-notes/repo-layout.md`.

## Gate table

| Claim | Evidence |
|---|---|
| the changed-suite run is green except one suite that is also red on origin/master | run table, `run-all.sh --changed` and the baseline block |
| the named suites pass | run table |
| no old path survives in a living file | zero-hit scan below |
| no new dead reference against origin/master | refcheck counts below |
| the path pins are load-bearing | two negative controls below |

## Run table

```
Command: bash tests/run-all.sh --changed origin/master --time
Exit: 1
Output:
run-all: --changed against 80ade329: 125 changed files -> 161 suites (160 named, the rest always-on)
... 160 suites reported ok, for example:
test-board-hermes                              ok (5s)
test-codex-hooks                               ok (9s)
test-docdrift-refcheck                         ok (0s)
test-install-modules                           ok (25s)
test-meta-docs-registry                        ok (8s)
test-test-affected-cache                       ok (5s)
test-test-affected-parallel                    ok (22s)
test-test-affected-replay                      ok (1s)
test-test-affected                             ok (23s)
test-wrap-land                                 ok (0s)
test-wrap-merge                                ok (76s)
test-wrap-rebase                               ok (14s)
run-all: FAILED -> test-no-personal-paths
run-all: 161 suites run, 0 skipped for missing tooling
Verdict: PASS WITH ONE BASELINE-RED SUITE (test-no-personal-paths, red on origin/master too, see below)
```

```
Command: bash tests/test-meta.sh
Exit: 0
Output:

=== Results ===
Passed: 930 / 930
All meta tests passed.
Verdict: PASS
```

```
Command: bash tests/gauntlet/tier1.sh
Exit: 0
Output:
PASS  tests/test-adopt.sh
== T1.5 gauntlet prep scripts lint
PASS  shellcheck -x tests/gauntlet/*.sh tests/gauntlet/cleanroom/*.sh tests/gauntlet/deploy/gauntlet-campaign

TIER1: GREEN
Verdict: PASS
```

```
Command: bash tests/test-docs-wiring.sh
Exit: 0
Output:
  PASS AC10: the sweep CATCHES the planted over-claim ('the multiplexer is enabled by default for every wave run')

=== 25/25 passed ===
Verdict: PASS
```

```
Command: bash tests/test-meta-docs-registry.sh
Exit: 0
Output:

=== Results ===
Passed: 120 / 120
All meta tests passed.
Verdict: PASS
```

```
Command: bash tests/test-install-modules.sh
Exit: 0
Output:
  PASS  'stray' writes nothing under HOME

== 67 passed, 0 failed ==
Verdict: PASS
```

```
Command: bash tests/test-board-hermes.sh
Exit: 0
Output:
case verb:
  ok   board hermes link --help

board-hermes: 79 passed, 0 failed
Verdict: PASS
```

```
Command: bash lib/system-design/doc-figures check
Exit: 0
Output:
doc-figures: ok (12 figures)
Verdict: PASS
```

## Baseline-red suite

`tests/test-no-personal-paths.sh` fails on a clean `git archive origin/master` copy with the same line, so it is not caused by this change and is left alone.

```
Command: bash tests/test-no-personal-paths.sh   (clean copy of origin/master)
Exit: 1
Output:
NOT ok - operator path/hostname still present:
docs/verification/front-door-rewrite.md:91:  warning: templates not found in ~/.git_template

Passed: 2 / 3
1 test(s) failed.
Verdict: RED on master (pre-existing)
```

```
Command: bash tests/test-no-personal-paths.sh   (this branch)
Exit: 1
Output:
NOT ok - operator path/hostname still present:
docs/verification/front-door-rewrite.md:91:  warning: templates not found in ~/.git_template

Passed: 2 / 3
1 test(s) failed.
Verdict: same failure as master
```

## Path scan and refcheck

Zero old paths in living files (every moved path, exact boundaries, dated records and tool-local `docs/` trees excluded):

```
Command: python3 scan of git ls-files for the old paths (docs/architecture.md ... adapters/hermes, rules/*.md, .skillspector-baseline.yaml)
Exit: 0
Output:
hits 0
Verdict: PASS
```

`bash lib/docdrift/refcheck.sh scan --repo .`, compared with a clean copy of origin/master:

| Scan | origin/master | this branch | New dead refs in living docs |
|---|---|---|---|
| default set (old set on master, widened to reference/ and guides/ here) | 35 docs, 1067 refs, 74 dead | 44 docs, 820 refs, 30 dead | 1 (`docs/guides/spine.md` names the gitignored `.claude/goals/`, a guide the old set never scanned) |
| wide set, living docs only | 1532 docs | 1527 docs | 0 |

The wide set also counts dated records. Those cite old paths on purpose and are not compared.

## Negative controls

Run after the moves were committed. `tests/test-docs-wiring.sh` reads none of the moved paths, so a path mutation there would stay green; the controls below target suites that read the new paths.

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-board-hermes.sh" "sed ... lib/sync/sweep/board-hermes"   (restore integrations/hermes -> adapters/hermes)
Exit: 0
Output:
    ok   the sweep's recorded state is what the brief reads
  case verb:
    ok   board hermes link --help

  board-hermes: 17 passed, 62 failed

Restore: git checkout HEAD -- lib/sync/sweep/board-hermes
Exit: 0 (green after restore)
Verdict: PASS
Verdict: PASS
```

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-registry-freshness-guard.sh" "sed ... hooks/ship-gate.sh"   (restore docs/reference/FEATURES.md -> docs/FEATURES.md)
Exit: 0
Output:
  warning: templates not found in ~/.git_template
  ok - a repo-supplied doc-projection checker is not executed by the gate
  ok - an install too old to scan another tree skips the arm with a note (exit 0)
  ---
  PASS=14 FAIL=1

Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
Verdict: PASS
```

## Rollback

Revert the squash commit of this branch. The change is paths and references only, with no data or state, so a revert restores the previous layout. Nothing outside the repo reads the new paths until the lead repoints the other repos.
