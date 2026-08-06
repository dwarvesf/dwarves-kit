# Proof of done: ledger-observatory feature `defect-correlation` (harness-observatory mega-goal, SG-02)

> Per-feature record. The canonical multi-feature index is
> [`../proof-of-done.md`](../proof-of-done.md); this file is its `defect-correlation` feature detail.

| | |
|---|---|
| **Profile** | data/CLI tool (behavioral, read-only) |
| **Proof class** | data-tool (recorded live run + negative control + reproducible) |
| **Spec** | [`../specs/SPEC-132-defect-correlation.md`](../specs/SPEC-132-defect-correlation.md) |

## Test design

`tests/test-defect-correlation.sh` builds its git-history fixture at test time (`git init` in
`mktemp -d` + a set of commits at controlled `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`), rather than
a committed nested repo (SPEC-132 DEC-005: a `.git` tree does not commit cleanly as tracked files
in this repo; every other suite in this tool already uses this same mktemp-per-run precedent). A
matching `kit_gates` fixture (5 shipped rids, one `.log` file each) points at the same 5 rid
slugs the git fixture's commit subjects mention. `git init --template=` disables this machine's
global Conventional-Commit `commit-msg` hook (DEC-006) so the disposable fixture repo is fully
independent of host git config.

### Golden fixture (generated at test time)

| rid | git commits (subject @ date, file) | Expected classification |
|---|---|---|
| `widget-parser` | `feat(widget-parser): add parser` @ 2026-01-01 (`parser.py`); `fix(widget-parser): handle empty input` @ 2026-01-06 (`parser.py`); `fix(widget-parser): handle unicode input` @ 2026-01-10 (`parser.py`) | `fix-followed` x2 (both later fixes, not collapsed) |
| `clean-feature` | `feat(clean-feature): add clean thing` @ 2026-02-01 (`clean.py`) -- no commit ever touches `clean.py` again | `clean` -- the FP-NC |
| `windowed-out` | `feat(windowed-out): add windowed thing` @ 2026-03-01 (`win.py`); `fix(windowed-out): patch late` @ 2026-05-30 (`win.py`, 90d later) | `clean` at the default 30d window; `fix-followed` at `--window-days 120` |
| `renamer` | `feat(renamer): add module` @ 2026-04-01 (`old.py`); `feat(renamer): rename old.py to new.py` @ 2026-04-02 (`new.py`); `fix(renamer): handle edge case in renamed module` @ 2026-04-05 (`new.py`) | `old.py` row present, `clean` (the ANCHOR is the earliest mention, 04-01, whose own file is `old.py`); no `new.py` row exists at all -- the rename is not followed (v1 limitation, SPEC-132 DEC-004) |
| `mergetest` | `feat(mergetest): base work` @ 2026-06-01 (`a.py`, main); `chore(mergetest): side branch change` @ 2026-06-02 (`b.py`, side branch); a 2-parent `--no-ff` merge, subject `fix(mergetest): merge should not count` @ 2026-06-03 | `a.py` row present, `clean`; the merge commit itself is absent from `git_fixes` entirely (proven directly against the adapter's return value, not just the correlation output) |

Plus an UNRELATED fix commit (`fix(something-else): unrelated patch` @ 2026-02-15, touching
`unrelated.py`) that must never contaminate `clean-feature`'s row.

## Confirmation run (recorded)

Command: `bash tests/test-defect-correlation.sh` -- 2026-07-04 (UTC clock), exit 0.

```
== D-rebuild: git_fixes + kit_gates materialize from the generated fixtures ==
PASS  D-rebuild kit_gates=5
PASS  D-rebuild git_fixes=12 (merge commit excluded)
== D-nc-merge: the merge commit itself never appears in git_fixes (--no-merges) ==
PASS  D-nc-merge merge commit sha absent from git_fixes
== D-miss: widget-parser is fix-followed on parser.py (default 30d window) ==
PASS  D-miss widget-parser/parser.py fix-followed (fix #1)
PASS  D-multi widget-parser/parser.py has BOTH later fixes as separate rows (not collapsed)
== F-nc: FALSE-POSITIVE negative control (load-bearing) ==
PASS  F-nc clean-feature labeled clean, no fix_sha
PASS  F-nc clean-feature never fix-followed
PASS  F-nc clean-feature reported honestly: clean, never fix-followed
PASS  F-nc-unrelated the unrelated fix() commit never contaminates clean-feature's row
== D-window: windowed-out is clean at the default window, fix-followed at a wider one ==
PASS  D-window windowed-out clean by default (fix is 90d later, past the 30d window)
PASS  D-window --window-days 120 flips windowed-out to fix-followed (the tunable is real)
== D-rename: rename boundary tracked per-filename, no crash, no false pairing ==
PASS  D-rename old.py (the anchor commit's own file) is tracked, stays clean
PASS  D-rename no renamer/new.py row exists at all (the rename is NOT followed, v1 limitation)
== F-nc-deliberate-break: prove the file-overlap join is load-bearing, not vacuous ==
PASS  F-nc-deliberate-break a file-blind (rid+time only) join WOULD flag clean-feature (the bug the real query avoids)
== O-plan: over-test pass on read_git_fixes() directly (edge cases beyond the fixture) ==
PASS  O1-missing-repo OK (empty columns+rows, no exception)
PASS  O2-not-a-repo OK (no .git -> empty, no crash)
PASS  O3-merge-excluded OK (merge sha absent)
PASS  O3-linear-commits-present OK (real commits still read)
== D-remat: delete-and-rematerialize is byte-identical (git fixture is canonical) ==
PASS  D-remat identical output
== D-nc: read-only negative control (the fixture git repo is never mutated) ==
PASS  D-nc fixture git history unchanged after rebuild+queries

== 20 passed, 0 failed ==
```

## FP negative control -- proven load-bearing (deliberate break)

The shipped `defect-correlation` SQL's `LEFT JOIN later_fix lf ON lf.file = sfl.file AND ...`
was deliberately patched (`cli.py`) to drop the `lf.file = sfl.file` condition, simulating
exactly the bug this design guards against: a correlation that matches ANY later fix() commit
regardless of file overlap, degrading "touching the same files" into "existed at the same time".
Re-run: **17 passed, 3 failed** -- both the FP-NC assertions (`clean-feature` should stay
`clean`) and one rename assertion went RED as expected (the file-blind join now also
incorrectly flags `renamer`/`old.py`, since SOME later fix() commit exists in the fixture's
history for it too). Restored (`cli.py` rewritten back to the shipped file-equality condition)
-> back to 20/20, exit 0. The NC is real, not decorative.

A second, independent falsifiability check (`F-nc-deliberate-break` in the suite) runs a
standalone broken query (rid+time only, no file-equality at all) against the SAME materialized
db and confirms it WOULD flag `clean-feature` -- proving the real shipped query's file-equality
condition is the thing keeping it clean, not an accident of the fixture's shape.

## Real-history run (2026-07-04)

Two separate repos, per SPEC-132's documented v1 scope (single-repo-per-materialization, no
cross-repo UNION query):

```
$ uv run ledger rebuild          # default repo: ops-toolkit
{ "kit_runs": 0, "kit_gates": 630, "git_fixes": 9585, "tide_moves": 0,
  "tide_tier_b_calls": 0, "tg_dialogs": 625, "learned": 58 }
$ uv run ledger defect-correlation --table
(0 rows)
```

```
$ LEDGER_OBS_GIT_REPO_DIR=~/workspace/<owner>/dwarves-kit uv run ledger rebuild
{ "kit_runs": 0, "kit_gates": 630, "git_fixes": 1869, "tide_moves": 0,
  "tide_tier_b_calls": 0, "tg_dialogs": 625, "learned": 58 }
$ uv run ledger defect-correlation --table
+---------------+---------------------------+---------------------------------------------+--------------+-------------------------------------------+---------------------------+-----------------------------------------------------------------------------------------------------+
| rid           | ship_ts                   | file                                        | label        | fix_sha                                    | fix_ts                    | fix_subject                                                                                          |
+---------------+---------------------------+---------------------------------------------+--------------+---------------------------------------------+---------------------------+-------------------------------------------------------------------------------------------------------+
| dag-wavefront | 2026-07-02T15:40:16+07:00 | _meta/BACKLOG.md                            | fix-followed | e5e96979b7b87add172798eb6131a639784bd960   | 2026-07-02T16:45:14+07:00 | fix(classify): kit-machinery hard-gate covers the enforcement/orchestration/telemetry libs (#114)  |
| dag-wavefront | 2026-07-02T15:40:16+07:00 | _meta/BACKLOG.md                            | fix-followed | d681dc076db979fba83808a6fb46241bd0ac08b8   | 2026-07-02T21:46:40+07:00 | fix(telemetry): stop two lane-detector false-flags (#121)                                            |
| dag-wavefront | 2026-07-02T15:40:16+07:00 | docs/specs/DECISION-BRIEF-dag-wavefront.md  | clean        |                                             |                           |                                                                                                       |
+---------------+---------------------------+---------------------------------------------+--------------+---------------------------------------------+---------------------------+-------------------------------------------------------------------------------------------------------+
(3 rows)
```

**Honest yield note:** across both scanned repos, only **1 of ~600 distinct shipped `kit_gates`
rids** (`dag-wavefront`) resolves via the rid-substring bridge into a matched git commit at all.
This is a real, stated limitation of the name-bridge heuristic (SPEC-132 DEC-002): most `kit`
run slugs are NOT literal substrings of the eventual commit subject in either repo's history
(commit subjects here follow a Conventional-Commit `type(scope): summary` shape that often
summarizes the CHANGE, not the run's internal slug). The one hit that DOES resolve is real and
useful (`_meta/BACKLOG.md`, a broadly-touched housekeeping file, was indeed touched by two
unrelated later `fix()` commits -- a legitimate but noisy signal, since almost any PR touches
that file; a more surgical v2 might exclude known "hub" files from the correlation, out of scope
here). `ops-toolkit`'s own history resolves ZERO of its ~600 rids (this repo's `kit_gates` rids
mostly name work shipped to OTHER repos, e.g. `dwarves-kit`, `dotfiles`; not a bug, a fact about
which repo's rids are recorded where).

## COVERAGE-DELTA

Baseline (a happy-path-only test) would cover: one shipped rid resolving to one commit, one later
fix on the same file within the window, one clean rid with no later fix. This sub-goal's
over-test pass ADDS: (1) a genuine 2-parent merge commit whose subject textually matches a rid
AND looks like a fix, proven excluded from `git_fixes` at the ADAPTER level (not just from the
correlation output, which could hide a subtler leak), (2) a rename inside a ship commit, proven
to not crash and to track per-filename honestly (the post-rename name is invisible, a stated v1
limitation rather than silently assumed correct), (3) TWO later fixes on the same file, proven
NOT collapsed into one row, (4) a windowing boundary case, proven the `--window-days` tunable
actually gates the classification (clean at 30d, fix-followed at 120d for the identical fixture
data), (5) an unrelated fix() commit touching only unrelated files, proven it never contaminates
an unrelated rid's row, (6) a missing repo path and a non-git directory, both proven skip-safe
(empty, no exception) at the adapter level directly. Covered: all 6 above, plus the FP-NC (a
clean rid is never flagged) proven load-bearing by a deliberate break AND a second independent
broken-query check. Not covered: a genuine cross-repo UNION query (v1 runs one repo at a time,
stated as a documented tradeoff, not built here); real rename-FOLLOWING across commits (a fix on
a post-rename name correlating back to a pre-rename ship anchor, explicitly out of scope per
SPEC-132); a `kit_gates` corpus where `kit_runs`/`start_ts`/`end_ts` are populated (both are
broken/NULL in this environment today, per SPEC-131 DEC-003 and the HANDOFF-flagged
pre-existing `read_kit()` issue; the design deliberately does not depend on either, see
SPEC-132 DEC-003).

## Regression (unaffected suites)

| Suite | Result |
|---|---|
| `tests/test-schema-parity.sh` | PASS (4/4, unchanged) |
| `tests/test-gate-yield.sh` | PASS (25/25, unchanged) |
| `tests/test-render-skill.sh` | PASS (30/30, unchanged) |
| `tests/test-schema-conform.sh` | PASS (11/11, unchanged) |
| `tests/test-docs-wiring.sh` | PASS (19/19, unchanged) |
| `tests/test-ledger-cli.sh` | 19/26 PASS, 7 FAIL -- pre-existing, unrelated (HANDOFF-flagged `kit_runs`/`read_kit()` subprocess env issue; reproduced identically via `git stash` before this branch, unchanged by this PR) |
| `tests/test-feedback.sh` | 30/39 PASS, 9 FAIL -- **newly confirmed pre-existing** in this local environment: reproduced IDENTICALLY via `git stash` before this branch (same 30/9 split with none of this PR's changes applied), so it predates and is unrelated to `git_fixes`/`defect-correlation`; not fixed here (out of scope), noted honestly per the same discipline SG-01 applied to `test-ledger-cli.sh` |

## Reproduce

```bash
cd ~/workspace/<owner>/ops-toolkit/tools/ledger-observatory
uv sync
bash tests/test-defect-correlation.sh                          # golden fixture + FP-NC + over-test (20/20)
bash tests/test-schema-parity.sh                                # regression: unaffected (4/4)
bash tests/test-gate-yield.sh                                   # regression: unaffected (25/25)
uv run ledger rebuild && uv run ledger defect-correlation --table                                    # real run: ops-toolkit (0 rows)
LEDGER_OBS_GIT_REPO_DIR=~/workspace/<owner>/dwarves-kit uv run ledger rebuild \
  && LEDGER_OBS_GIT_REPO_DIR=~/workspace/<owner>/dwarves-kit uv run ledger defect-correlation --table  # real run: dwarves-kit (3 rows)
```
