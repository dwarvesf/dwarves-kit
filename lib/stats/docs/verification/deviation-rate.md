# Proof of done: ledger-observatory feature `deviation-rate` (harness-observatory mega-goal, SG-03)

> Per-feature record. The canonical multi-feature index is
> [`../proof-of-done.md`](../proof-of-done.md); this file is its `deviation-rate` feature detail.

| | |
|---|---|
| **Profile** | data/CLI tool (behavioral, read-only) |
| **Proof class** | data-tool (recorded live run + negative control + reproducible) |
| **Spec** | [`../specs/SPEC-133-deviation-rate.md`](../specs/SPEC-133-deviation-rate.md) |

## Test design

`tests/test-deviation-rate.sh` builds its git-history fixture at test time (`git init` in
`mktemp -d` + a set of commits at controlled `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`), the same
precedent as `test-defect-correlation.sh` (SPEC-132 DEC-005: a `.git` tree does not commit
cleanly as tracked files in this repo). The 7 implementation-notes fixture files are plain
(untracked) files under the fixture repo's `docs/implementation-notes/` -- `read_impl_notes` is
a filesystem walk, not a git read, so git-tracking them is not required.

### Golden fixture (generated at test time)

| slug | shape | git bridge | Expected class |
|---|---|---|---|
| `clean-notes` | zero-marker, 0 entries | `feat(clean-notes): ...` @ 2026-02-01, never fixed | `CLEAN` -- the HONEST-ZERO NC |
| `suspect-notes` | zero-marker, 0 entries | `feat(suspect-notes): ...` @ 2026-03-01; `fix(suspect-notes): ...` @ 2026-03-06 (same file, within 30d) | `SUSPECT` |
| `windowed-out-notes` | zero-marker, 0 entries | `feat(windowed-out-notes): ...` @ 2026-04-01; `fix(windowed-out-notes): ...` @ 2026-06-30 (same file, ~90d later) | `CLEAN` @ default 30d window; `SUSPECT` @ `--window-days 150` |
| `underspecced-notes` | 4 real entries (2026-05-01..04) | none needed | `UNDER-SPECCED` (>= default `--under-specced-min 3`); `OTHER` @ `--under-specced-min 5` |
| `malformed-notes` | zero-marker line AND 2 real entries (contradictory) | none needed | `n_deviations=2`, `zero_marker=false` (forced), a stderr warning logged, class `OTHER` |
| `legacy-notes` | free-form prose, no dated header, no marker (predates the hook convention) | none needed | `n_deviations=0`, `zero_marker=false`, class `OTHER` |
| `multi-same-day` | 2 entries dated the SAME day | none needed | `n_deviations=2` (not deduped), class `OTHER` |

Plus an UNRELATED fix commit (`fix(something-else): unrelated patch` @ 2026-02-15, touching
`unrelated.py`) that must never contaminate `clean-notes`'s row.

## Confirmation run (recorded)

Command: `bash tests/test-deviation-rate.sh` -- 2026-07-04 (UTC clock), exit 0.

```
== I-rebuild: impl_notes + git_fixes materialize from the generated fixtures ==
PASS  I-rebuild impl_notes=7
PASS  I-rebuild git_fixes=6 (one file per commit, 6 commits)
== I-classify: exact classification per slug (golden fixture, all 4 named classes) ==
PASS  I-classify clean-notes -> CLEAN (the honest-zero NC)
PASS  I-classify suspect-notes -> SUSPECT (a later fix() touches the anchor's own file)
PASS  I-classify windowed-out-notes -> CLEAN at the default 30d window
PASS  I-classify underspecced-notes -> UNDER-SPECCED (4 >= 3), first/last_ts real
PASS  I-classify malformed-notes -> counted as entries (n=2), zero_marker forced false, class OTHER
PASS  I-classify legacy-notes -> pre-convention file, n=0 zero_marker=false, class OTHER
PASS  I-classify multi-same-day -> n_deviations=2 (not deduped), class OTHER
== I-window: windowed-out-notes flips CLEAN -> SUSPECT once --window-days widens ==
PASS  I-window --window-days 150 flips windowed-out-notes to SUSPECT (the tunable is real)
== I-tunable: --under-specced-min changes the UNDER-SPECCED cutoff ==
PASS  I-tunable --under-specced-min 5 demotes underspecced-notes (4 < 5) off UNDER-SPECCED
== F-nc-deliberate-break: prove the file-overlap bridge is load-bearing, not vacuous ==
PASS  F-nc-deliberate-break a file-blind (slug+time only) join WOULD flag clean-notes (the bug the real query avoids)
== O-plan: over-test pass on read_impl_notes() directly (edge cases beyond the fixture) ==
PASS  O1-missing-repo OK (empty columns+rows, no exception)
PASS  O2-no-impl-notes-dir OK (no docs/implementation-notes anywhere -> empty, no crash)
PASS  O3-empty-file OK (n_deviations=0, zero_marker=False, no crash)
PASS  O4-nested-worktree-not-double-counted OK (hidden-dir pruning works)
== O-malformed: the malformed-file stderr warning is actually logged (not silently eaten) ==
PASS  O-malformed stderr warning names the malformed file
PASS  O-malformed stderr warning names malformed-notes.md specifically
== I-remat: delete-and-rematerialize is byte-identical (fixture files canonical) ==
PASS  I-remat identical output
== I-nc: read-only negative control (fixture files never mutated) ==
PASS  I-nc fixture impl-notes files byte-identical after rebuild+queries
== A-dense: rolling median n_deviations over threshold stages ONE unknown-density proposal ==
PASS  A-dense unknown_density staged
PASS  A-dense exactly ONE proposal staged
== A-sparse: below-threshold density stages NOTHING ==
PASS  A-sparse unknown_density NOT fired
PASS  A-sparse nothing staged
== A-dedup: --propose twice on the same dense state stages ONCE (idempotent) ==
PASS  A-dedup re-propose does not duplicate

== 25 passed, 0 failed ==
```

## Honest-zero NC -- proven load-bearing (deliberate break)

The shipped `deviation-rate` SQL's `suspect` CTE (`JOIN later_fix lf ON lf.file = af.file AND
...`) was deliberately patched (`cli.py`) to drop the `lf.file = af.file` condition, simulating
exactly the bug this design guards against: a correlation that matches ANY later fix() commit
regardless of file overlap, degrading "a later fix on the same files" into "existed at the same
time". Re-run: **24 passed, 1 failed** -- `I-classify clean-notes` went RED as expected
(`clean-notes` flipped from `CLEAN` to `SUSPECT`, since the unrelated fix commit @ 2026-02-15 is
temporally after `clean-notes`'s anchor @ 2026-02-01 and within any reasonable window, even
though it touches an entirely unrelated file). Restored (`cli.py` rewritten back to the shipped
file-equality condition) -> back to 25/25, exit 0. The NC is real, not decorative.

A second, independent falsifiability check (`F-nc-deliberate-break` in the suite) runs a
standalone broken query (slug+time only, no file-equality at all) against the SAME materialized
db and confirms it WOULD flag `clean-notes` -- proving the real shipped query's file-equality
condition is the thing keeping it clean, not an accident of the fixture's shape.

## Real-corpus run (2026-07-04)

Two separate repos, per SPEC-133's documented v1 scope (single-repo-per-materialization, shared
with `git_fixes`'s own v1 scope, no cross-repo UNION query):

```
$ uv run ledger rebuild          # default repo: ops-toolkit
{ "kit_runs": 0, "kit_gates": 654, "git_fixes": 9611, "impl_notes": 233, "tide_moves": 0,
  "tide_tier_b_calls": 0, "tg_dialogs": 625, "learned": 58 }
$ uv run ledger deviation-rate --json | <class distribution>
{'OTHER': 108, 'UNDER-SPECCED': 125, 'CLEAN': 0, 'SUSPECT': 0}
```

```
$ LEDGER_OBS_GIT_REPO_DIR=~/workspace/tieubao/dwarves-kit uv run ledger rebuild
{ "kit_runs": 0, "kit_gates": 654, "git_fixes": 1889, "impl_notes": 77, "tide_moves": 0,
  "tide_tier_b_calls": 0, "tg_dialogs": 625, "learned": 58 }
$ uv run ledger deviation-rate --json | <class distribution>
{'UNDER-SPECCED': 51, 'OTHER': 26, 'CLEAN': 0, 'SUSPECT': 0}
```

Top `UNDER-SPECCED` rows by `n_deviations` in `dwarves-kit`: `dag-wavefront` (18),
`north-star-wave` (11), `mega-merge-guard` (8), `grill-conditioning` (7, also the one
MALFORMED file found in the real dwarves-kit corpus: a zero-marker line AND 7 real entries),
`v3-meta-agent` (7).

Two malformed files confirmed in the real ops-toolkit corpus at design time (and reconfirmed at
this real run, both logged to stderr during `rebuild`):
`tools/vps-mon/docs/implementation-notes/SPEC-075-mini-launchd-collector.md` (21 real entries)
and `tools/safari-tabs/extension/docs/implementation-notes/parity-verbs.md` (2 real entries).

**Honest yield note (the class distribution the classifier was designed to reveal, not
manufacture):** across BOTH scanned repos, **zero rows carry `zero_marker=true`** today (`SELECT
count(*) FROM impl_notes WHERE zero_marker` returns 0 in both materializations). This means
`CLEAN` and `SUSPECT` are both empty in the real run -- NOT because the classifier is broken
(proven correct against the golden fixture above, including the load-bearing honest-zero NC),
but because the real corpus simply has not yet produced a genuinely honest-zero-deviation
implementation-notes file: every real file surveyed either logs at least one real dated entry,
or predates the hook's entry-header/marker convention entirely (the `OTHER` bucket, DEC-005).
Stated plainly, the same discipline SG-01 applied to "100% NULL `caught`" and SG-02 applied to
"1 of ~600 rids resolves": a benchmark that reports a suspiciously clean CLEAN/SUSPECT split
without a single real data point behind it would be worse than reporting the honest zero.

## Cross-suite regression found + fixed (Build)

Not anticipated in the goal file; found while running the regression suites after `impl_notes`
first landed. `test-ledger-cli.sh`, `test-feedback.sh`, and `test-gate-yield.sh` never override
`LEDGER_OBS_GIT_REPO_DIR` (SG-02's `git_fixes` already silently defaulted to the real repo in
these suites, but `git_fixes` emits no stderr and adds no anomaly detector, so it never
surfaced). `impl_notes` introduces two new failure surfaces once left un-isolated:

- **Before the fix**, direct runs showed: `test-ledger-cli.sh` 18/26 (one NEW failure,
  `R-remat`: a stderr malformed-file warning leaked into the byte-identical comparison across a
  lazy rebuild boundary); `test-feedback.sh` 32/39, with `F-nc-noise` itself now RED (fewer total
  failures than the 9-failure baseline, but a DIFFERENT, shifted set: `unknown-density` spuriously
  fired against the real corpus's genuine deviation density inside the load-bearing noise-floor
  negative control, exactly the class of bug this mega-goal's Quality bar names as unacceptable
  -- "an honest zero-deviation note never flagged SUSPECT" generalizes to "a noise-floor state
  never proposes").
- **The fix:** one `LEDGER_OBS_GIT_REPO_DIR="$FIX/nonexistent-git-repo"` isolation line added to
  each of the 3 suites (matching their existing "absent -> skip-safe" convention for the other
  env vars; zero assertion-logic changes).
- **After the fix, `git stash`-verified against the true baseline:** `test-ledger-cli.sh` 19/26
  (7 fail, EXACT pre-existing count); `test-feedback.sh` 30/39 (9 fail, EXACT pre-existing
  count, same failing test NAMES as the pre-`impl_notes` baseline); `test-gate-yield.sh` 25/25
  (was already passing, confirmed unaffected either way).

## COVERAGE-DELTA

Baseline (a happy-path-only test) would cover: one zero-marker slug with zero later fixes
(CLEAN), one zero-marker slug with a later fix on the same file (SUSPECT), one slug with
enough logged deviations (UNDER-SPECCED). This sub-goal's over-test pass ADDS: (1) a windowing
boundary case, proven the `--window-days` tunable actually gates the classification (CLEAN at
30d, SUSPECT at 150d for the identical fixture data), (2) an `--under-specced-min` boundary case,
proven that tunable is real too (UNDER-SPECCED at the default 3, demoted to OTHER at 5), (3) a
malformed file (BOTH a zero-marker line and real entries), proven counted as entries with
`zero_marker` forced `False` and a stderr warning ACTUALLY logged (not merely computed and
discarded), (4) a pre-convention legacy file (neither a dated header nor a marker line, a real
shape confirmed in the corpus), proven classified `OTHER` rather than silently coerced into one
of the 3 named classes, (5) multiple entries dated the SAME day, proven not deduped, (6) a
missing repo path and a directory with no `docs/implementation-notes` anywhere, both proven
skip-safe (empty, no exception) at the adapter level directly, (7) a nested `.claude/worktrees/
<x>` copy of the same repo, proven NOT double-counted (the real risk confirmed present in
dwarves-kit at design time), (8) an empty impl-notes file, proven to parse to zero entries with
no crash, (9) the unknown-density anomaly's dense/sparse/idempotent-re-propose cases. Covered:
all 9 above, plus the honest-zero NC (a CLEAN slug is never flagged SUSPECT) proven load-bearing
by a deliberate break AND a second independent broken-query check. Not covered: a genuine
cross-repo UNION query (v1 runs one repo at a time, a documented tradeoff shared with
`git_fixes`'s own v1 scope, not built here); a real corpus row that actually carries
`zero_marker=true` (today's real corpus has none -- a stated, not hidden, limitation of the DATA,
not the classifier, which is separately proven correct against the golden fixture); parsing a
note's "files touched" out of its own free-form prose (Approach 3 in SPEC-133, rejected -- the
file list used for correlation always comes from `git_fixes`).

## Regression (unaffected suites, verified after the DEC-004 isolation fix)

| Suite | Result |
|---|---|
| `tests/test-schema-parity.sh` | PASS (4/4, unchanged) |
| `tests/test-gate-yield.sh` | PASS (25/25, unchanged) |
| `tests/test-defect-correlation.sh` | PASS (20/20, unchanged) |
| `tests/test-render-skill.sh` | PASS (30/30, unchanged) |
| `tests/test-schema-conform.sh` | PASS (11/11, unchanged) |
| `tests/test-docs-wiring.sh` | PASS (19/19, unchanged) |
| `tests/test-ledger-cli.sh` | 19/26 PASS, 7 FAIL -- pre-existing, unrelated (HANDOFF-flagged `kit_runs`/`read_kit()` subprocess env issue; EXACT count restored via the DEC-004 isolation fix, `git stash`-verified) |
| `tests/test-feedback.sh` | 30/39 PASS, 9 FAIL -- pre-existing, unrelated (SG-02-confirmed; EXACT count + failing-test-name set restored via the DEC-004 isolation fix, `git stash`-verified) |

## Reproduce

```bash
cd ~/workspace/tieubao/ops-toolkit/tools/ledger-observatory
uv sync
bash tests/test-deviation-rate.sh                              # golden fixture + honest-zero NC + over-test (25/25)
bash tests/test-schema-parity.sh                                # regression: unaffected (4/4)
bash tests/test-gate-yield.sh                                   # regression: unaffected (25/25)
bash tests/test-defect-correlation.sh                            # regression: unaffected (20/20)
bash tests/test-ledger-cli.sh                                    # regression: pre-existing 19/26 (7 fail), unaffected
bash tests/test-feedback.sh                                      # regression: pre-existing 30/39 (9 fail), unaffected
uv run ledger rebuild && uv run ledger deviation-rate --table                                    # real run: ops-toolkit (233 rows)
LEDGER_OBS_GIT_REPO_DIR=~/workspace/tieubao/dwarves-kit uv run ledger rebuild \
  && LEDGER_OBS_GIT_REPO_DIR=~/workspace/tieubao/dwarves-kit uv run ledger deviation-rate --table  # real run: dwarves-kit (77 rows)
```
