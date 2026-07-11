# Proof of done: mega review dashboard (SPEC-197, harness-loop sub-goal 07)

VERDICT: PASS

## Acceptance criteria (goal file `_meta/megagoals/harness-loop/goals/07-mega-review-dashboard.md`)

1. Spec; Design block = the data-source join diagram (ledger + gh + proof paths).
2. Build the compose; render for an archived mega with real ledgers; screenshots (overview /
   group / attention state).
3. Wire at TIER-4 close behind the existing `TIER4_CLOSE` knob; NC: knob off -> no render, run
   captured.
4. Honest-empty: a mega with no ledger rows renders a page saying so, never fabricated rows
   (captured).
5. Suite green.

## Command run: `bash tests/test-mega-review.sh`

```
ok - review exits 0 and writes the requested --out path
ok - 01-populated group is present
ok - both GATE rows for 01-populated render (not just the last)
ok - TOKENS lines SUM across retries (100+200=300, 50+75=125), not last-wins
ok - proof-of-done best-effort link found for 01-populated (bare-slug candidate)
ok - 02-noledger group is present
ok - 02-noledger renders the honest 'no ledger rows' message
ok - 02-noledger's proof link is honestly unlinked (no fabricated path)
ok - 03-nobranch group renders despite no goal file at all
ok - rid isolation: 02-noledger's group carries none of 01-populated's ledger rows
ok - honest-empty NC: review still exits 0 on a mega with zero ledger rows
ok - honest-empty NC: the page states the absence plainly (a banner)
ok - honest-empty NC: zero <tr> rows anywhere (never fabricated)
ok - attention: an OK sub-goal renders WITHOUT the open attribute (collapsed)
ok - attention: a CLAIM-UNVERIFIED sub-goal renders WITH the open attribute (needs eyes)
ok - footer: staged candidates honest-dash when _meta/backlog-staging.md is absent
ok - footer: learned-ledger honest-dash when STATS_LEARNED_MD is unset
ok - footer: unpaid-debt is a REAL 0 (weekend-batch.sh resolved and legitimately found nothing), not honest-dash
ok - footer: staged candidates counts [staged] blocks only + computes oldest age
ok - footer: learned-ledger counts status=queued rows only (2 of 3)
ok - usage: missing --html is a clear error
ok - usage: missing slug is a clear error
ok - OUTCOME-only ledger: review still exits 0
ok - OUTCOME-only ledger: renders the DISTINCT 'OUTCOME markers exist, no GATE row' message
ok - OUTCOME-only ledger: did NOT collapse into the plain 'no ledger rows' message
ok - OUTCOME-only ledger: no fabricated table
----
26 passed, 0 failed
```

Exit: 0.

## Real-archived-mega render (goal step 2): screenshots

Rendered from the REAL, live gate/run ledger corpus at
`~/.local/state/dwarves-kit/logs/runs/*.log` (this machine's actual harness-ops and
kit-modularity run history -- no fixture, no synthetic data), against the archived megas at
`_meta/megagoals/_archive/harness-ops` and `_meta/megagoals/_archive/kit-modularity`:

```
Command: bash lib/mega.sh review harness-ops --html \
  --megagoals-root _meta/megagoals/_archive --code-root . --base master --out <tmp>/harness-ops-review.html
Exit: 0
Output: <tmp>/harness-ops-review.html (matches lib/mega.sh status's own real rollup: 12/13 ok, 1 drift)

Command: bash lib/mega.sh review kit-modularity --html \
  --megagoals-root _meta/megagoals/_archive --code-root . --base master --out <tmp>/kit-modularity-review.html
Exit: 0
```

Screenshots (`docs/proof/loop-07-mega-dashboard/`, taken headless via Playwright/Chromium):

- **`01-overview.png`** -- the harness-ops dashboard, full page: 12 real `OK` sub-goal groups
  collapsed (green left border, no `open` attribute) + `01-config-resolver`'s real
  `CLAIM-UNVERIFIED` group expanded (red left border, `open`) -- the sub-goal genuinely landed
  on master via a direct commit with no PR, exactly the class this classifier exists to catch.
  Footer shows honest-dash for `staged candidates`/`learned-ledger queued` (neither consumer
  file exists on this run) and a real `unpaid debt (7d window): 1`.
- **`02-subgoal-group.png`** -- harness-ops's `02-wire-ledger` group expanded: the real GATE
  table (11 rows, ran/skipped + reasons, verbatim from the real ledger), honest `tokens: -`
  (no TOKENS line was recorded for this real 2026-07-06 run), real PR #211 state (MERGED, CI
  passing, merged timestamp, live PR URL via `gh pr view`), and the best-effort proof-of-done
  link resolved to the real `docs/verification/wire-ledger.md` (the bare-slug candidate).
- **`03-attention-state.png`** -- close-up of `01-config-resolver`'s `CLAIM-UNVERIFIED` group:
  no PR/branch data (it landed directly on master), honest "(no ledger rows for this sub-goal)"
  (its goal file carries no `**Branch:**` line, so no rid can be derived), and an honestly
  unlinked proof-of-done (its real proof lives in `RUN_REPORT.md` prose with no separate file
  -- the best-effort search correctly does not fabricate a link).

## TIER-4 wiring (goal step 3): NC captured in `tests/test-tier4-close.sh`

```
Command: bash tests/test-tier4-close.sh
...
PASS mega-review wiring: TIER4_CLOSE=1 renders $dir/REVIEW.html at close
PASS mega-review wiring: the close narrates the render
...
PASS mega-review wiring NC: TIER4_CLOSE=0 -> no REVIEW.html (render never attempted)
PASS mega-review wiring NC: no render narration line (close never ran)
...
----
ALL PASS
```

Exit: 0. Scenario A (TIER4_CLOSE=1, the default) produces `$DA/REVIEW.html` and the narration
line `mega-review dashboard rendered: ...`; scenario F (TIER4_CLOSE=0) produces neither --
proving the render is fully gated on the SAME knob every other close step already uses, no
new env var.

## Honest-empty NC (goal step 4): captured in `tests/test-mega-review.sh`

```
Command: bash tests/test-mega-review.sh (section 5)
ok - honest-empty NC: review still exits 0 on a mega with zero ledger rows
ok - honest-empty NC: the page states the absence plainly (a banner)
ok - honest-empty NC: zero <tr> rows anywhere (never fabricated)
```

A fixture mega (`emptymega`, 2 unchecked sub-goals, real `**Branch:**` lines, zero matching
ledger files under the sandboxed `DWARVES_KIT_LOG_DIR`) renders `<title>mega review:
emptymega</title>` plus the banner `No ledger rows found for ANY sub-goal in this mega yet.
Every group below reflects ROADMAP + git-truth only; re-render once gates have been recorded.
Never fabricated.` -- and the rendered HTML contains ZERO `<tr>` elements anywhere in the
document (asserted directly against the file, not just the banner's presence).

## COVERAGE-DELTA (over-test on the render's data joins)

Beyond the two required NCs, `tests/test-mega-review.sh` adds:
- **TOKENS summation across retries** (section 1): a fixture ledger with TWO `build` attempts
  (100/50/10/5 then 200/75/0/0 tokens) renders `in=300 out=125 cache_read=10 cache_create=5`
  -- proves the composer sums every TOKENS line rather than reading only the last (a real
  risk: a naive "last TOKENS line wins" implementation would have under-reported cost on any
  sub-goal that needed a retry).
- **Rid isolation** (section 4): a fixture with two sub-goals, only one carrying ledger data,
  asserts the OTHER sub-goal's rendered `<details>` block contains NONE of the first one's
  ledger text -- proves the per-sub-goal join does not leak across groups (a plausible bug
  class if the ledger were read once and grep'd per-group instead of re-parsed per rid).
- **A goal file that does not exist at all** (section 3, `03-nobranch`): the sub-goal still
  renders (git-truth honest-absence, no branch to resolve, no ledger to look up) instead of
  crashing on a missing file.
- **Footer honest-dash vs. a REAL zero, distinguished** (section 7): `unpaid debt` reads `0`
  (a real count from a reachable, empty `weekend-batch.sh list`) while `staged candidates`/
  `learned-ledger queued` read `-` (their consumer files are genuinely absent/unset) --
  proves the composer does not collapse "source absent" and "source empty" into the same
  signal, the exact distinction the goal file's "honest-dash when absent" language requires.
- **Attention open/collapse, both directions** (section 6): an `OK`-classified group is
  asserted to lack the `open` attribute (collapsed) AND a `CLAIM-UNVERIFIED` group is
  asserted to carry it (expanded) -- both polarities checked, not just one.
- **Usage guards** (section 8): missing `--html` and missing `<slug>` both produce a clear,
  distinct stderr message and a nonzero exit, not a silent no-op.

Real-corpus finding (not a bug, a data-quality observation, recorded in SPEC-197 DEC-007 and
`docs/implementation-notes/loop-07-mega-dashboard.md`): the real shared ledger corpus carries
one rid (`kitmod-03-subsystem-commands`) with OUTCOME lines but zero GATE lines -- the
composer correctly renders "(no GATE rows recorded... OUTCOME markers exist with no paired
GATE row)" for it rather than a fabricated or crashed render. This exact honest-degrade path
is now a DEDICATED planted-fixture test (`tests/test-mega-review.sh` section 9,
`outcomeonlymega`, added after the real-corpus anomaly surfaced it): asserts the DISTINCT
message renders, the plain "no ledger rows" message does NOT wrongly fire, and no `<table>`
is fabricated.

## `lib/mega.sh status`'s existing contract: unchanged

```
Command: bash tests/test-mega.sh
...
PASS=16 FAIL=0
```

Exit: 0. All 16 pre-existing checks pass unmodified -- adding `review` as a second verb + the
shared `--html`/`--out` flags to `_parse_flags` did not change `status`'s behavior.

## Full suite

Every `run:` line in `.github/workflows/test.yml` (48 test files, including the new
`tests/test-mega-review.sh` entry) passes locally:

```
Command: 45 of the 48 CI test files, run in one batch (excludes test-e2e.sh,
         test-orchestrate-wavefront.sh, test-pane-viewer.sh -- run separately below, per
         the repo's documented local-flake precedent for these three, RUN_REPORT.md
         "harness-ops")
Exit: 0 for all 45 (45/45 RC=0)

Command: bash tests/test-e2e.sh              -- Exit 0, 20/20 passed
Command: bash tests/test-orchestrate-wavefront.sh -- Exit 0, ALL PASS
Command: bash tests/test-pane-viewer.sh      -- Exit 0, ALL PASS
```

48/48 CI-wired test files green, 0 regressions.

## Rollback

Purely additive: one new lib file (`lib/mega-review.py`), one new verb on an existing
orphan file (`lib/mega.sh`'s `review` case arm), ~16 new lines in `orchestrate.sh`'s
`_tier4_close` (best-effort, wrapped in `if/else`, never touches the close's own return
code), two new/extended test files. No schema change, no existing-file deletion, no change
to `lib/mega.sh status`'s contract. Revert = `git revert` the commit(s); every existing
caller of `lib/mega.sh status` or `orchestrate.sh` with `TIER4_CLOSE=0` is byte-identical
either way.
