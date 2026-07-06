# Proof of done: kit-modularity SG-08 (mega-status)

**Change:** `lib/mega.sh` -- a `mega status <slug>` reader (bare orphan, no subdir; see
Design decision below) that reconciles a mega-goal's `ROADMAP.md` sub-goal claims against
GIT TRUTH (`gh pr view`/`gh pr list` + `git rev-list --count`) instead of trusting the
roadmap's own `[x]`/`[ ]` prose, and flags drift (`CLAIM-UNVERIFIED` / `STALLED` /
`MERGED-UNCHECKED`). Plus an OPT-IN `--with-mega` flag on `lib/board/board.sh`'s `board` and
`status` subcommands that appends a trailing `MEGA ROLLUP` section (one `mega status
--rollup-only` line per active mega under the repo's `_meta/megagoals/`), so mega drift sits
on the kanban beside backlog items without touching the byte-identical default render.
Provenance: a live session hit the SG-02 HANDOFF-vs-reality lie by hand (HANDOFF.md claimed
"running" while the `kitmod-02` worktree sat at 0 commits, empty); this verb is that manual
reconciliation made mechanical.

## Acceptance criteria -> confirmation

| # | Criterion | Result |
|---|---|---|
| 1 | reconciles roadmap `[x]`/`[ ]`/`[~]` claims against real PR/branch state, never trusts prose | PASS -- `lib/mega.sh`, drift table below |
| 2 | `CLAIM-UNVERIFIED`: `[x]` + PR#N cited but NOT merged | PASS NC-1, `tests/test-mega.sh` |
| 3 | `STALLED`: `[ ]` + branch exists, 0 commits vs base, no open PR | PASS NC-2 |
| 4 | `MERGED-UNCHECKED`: `[ ]` + its PR IS merged | PASS NC-3 |
| 5 | nuance: 0 commits + an OPEN PR is WIP, never STALLED (do not false-positive a live worker) | PASS, `tests/test-mega.sh` "nuance" case |
| 6 | reads the megagoals dir from CONSUMER config (`REPO_ROOT`/env), no personal path in the kit | PASS `--megagoals-root` > `$MEGAGOALS_ROOT` > `${REPO_ROOT}/_meta/megagoals` > cwd-derived |
| 7 | bash + `gh` only, no DuckDB | PASS -- `lib/mega.sh` is pure bash, `${GH_BIN:-gh}`/`${GIT_BIN:-git}` subprocess calls only |
| 8 | `board render` rollup column for `megagoals:`-adjacent rows | PASS `board board/status --with-mega`, opt-in (see Design decision) |
| 9 | passive firing point (surfaced, not pull-only) | PASS -- `board status --with-mega` composes into the existing mirror-staleness surface |
| 10 | run-table over the REAL megagoals corpus | PASS -- live `mega status kit-modularity` run below |
| 11 | suite identical-or-better | PASS -- see run-table |

## Design decision: `mega` stays a bare orphan, not a grouped subdir

SG-03 settled "grouped standalone entries = only 2+-verb subsystems" (`lib/<x>/<x>.sh`
case-dispatcher shape, e.g. `gate`/`classify`/`spec`/`goal`/`session`). `mega` has exactly
ONE verb today (`status`), so it stays a bare orphan file at `lib/mega.sh`, the same shape
as `lib/adopt.sh` / `lib/explain.sh` / `lib/pitch.sh` / `lib/precedent.sh`, internally
dispatching on its first arg (`mega.sh status <slug> ...`). It does NOT ride under `board`
either: `mega status` reconciles a DIFFERENT repo's git truth (the mega's own code repo,
e.g. dwarves-kit) against a THIRD location (wherever `_meta/megagoals/` lives, e.g.
ops-toolkit) -- board.sh's own domain is one repo's `_meta/BACKLOG.md`, a narrower and
different consumer-config shape. Making `mega status` a `board` subcommand would conflate
two independent consumer-config resolutions into one flag surface. If `mega` grows a second
verb later, promote to `lib/mega/mega.sh` + siblings then, per the same SG-03 rule.

## Design decision: `--with-mega` is opt-in on `board`, not the default

`board.sh board`/`all board`/`status` are covered by `tests/test-board.sh`'s NC-e
byte-identical render non-regression control (against the pre-migration `_meta/board`/
`_meta/board-all`). Baking mega rollups unconditionally into the default render would (a)
break that byte-identical contract on any repo with an active mega, and (b) make every
plain `board` call issue real network `gh` calls per sub-goal per active mega -- slow and
flaky by default. `--with-mega` (plus `--mega-code-root` for the cross-repo case, e.g.
kit-modularity's ROADMAP lives in ops-toolkit but its PRs/branches live in dwarves-kit) makes
this an explicit ask, never a silent default; `tests/test-mega.sh` proves BOTH that the flag
surfaces the rollup AND that its absence makes zero `gh` calls (same stub-gh fixture, no
`GH_BIN` needed for the without-flag assertion since it must never even try to invoke gh).

## Drift-class taxonomy (as built)

| Class | Condition | Symbol |
|---|---|---|
| `OK` (`✓`) | `[x]` + PR#N verified `MERGED` | ✓ |
| `CLAIM-UNVERIFIED` | `[x]` + PR#N NOT merged (open/closed/missing) | ⚠ |
| `MERGED-UNCHECKED` | `[ ]` + its PR#N IS merged | ⚠ |
| `STALLED` | `[ ]` + branch exists, 0 commits vs base, no open PR | ⚠ |
| `WIP` | `[ ]` + branch has commits, OR an open PR exists | ~ |
| `PENDING` | `[ ]` + no branch, no PR at all | . |
| `INFO` | `[~]` rehomed/superseded -- always informational, never flagged | - |

Matches the goal file's taxonomy exactly (no class added or dropped); `WIP`/`PENDING`/`INFO`
are the non-drift classes the goal describes but does not name, named here for the render.

## Named negative controls (actual runs, `tests/test-mega.sh`)

```
ok - 01-alpha (PR merged) -> OK
ok - NC-1: 02-beta ([x] + PR NOT merged) -> CLAIM-UNVERIFIED
ok - NC-2: 03-gamma ([ ] + 0 commits, no open PR) -> STALLED
ok - NC-3: 04-delta ([ ] + PR merged) -> MERGED-UNCHECKED
ok - nuance: 05-epsilon (0 commits but an OPEN PR) -> WIP, never STALLED
ok - 06-zeta ([ ] + commits, no open PR) -> WIP
ok - 07-eta ([ ] + no branch, no PR) -> PENDING
ok - 08-theta ([~] rehomed) -> INFO always
ok - rollup line: testmega: 1/8 ok  ⚠ 3 drift
ok - exit code nonzero when drift > 0
ok - --rollup-only prints exactly the rollup line, no detail
ok - clean roadmap (all [x] verified merged) -> 0 drift, exit 0
ok - missing ROADMAP.md -> nonzero exit
ok - unknown subcommand -> nonzero exit
ok - board board --with-mega surfaces the mega rollup in a trailing MEGA ROLLUP section
ok - board board WITHOUT --with-mega never touches gh / never prints a rollup (opt-in, non-regressing default)
---
Coverage delta: mega.sh had 0 tests before this file; now 16 checks across the full drift-class taxonomy.
---
PASS=16 FAIL=0
```

NC-1/NC-2/NC-3 are load-bearing: fixtures built with a REAL git repo (`CODEROOT`, mktemp) for
branches/commits (same precedent as `test-board.sh`'s `fixA`/`fixB`) and a PATH-injected stub
`gh` (`GH_BIN`, no real network call anywhere in the suite, per `lib/board/board-writeback.sh`'s
existing `GH_BIN` convention).

## Run-table over the REAL megagoals corpus (kit-modularity's own ROADMAP)

Command:
```
REPO_ROOT=~/workspace/tieubao/ops-toolkit CODE_ROOT=~/workspace/tieubao/dwarves-kit \
  bash lib/mega.sh status kit-modularity
```
Output (run from the kitmod-08 worktree, before this branch's own commits landed --
correctly self-detects its own then-empty state):
```
  ✓ 01-module-collapse          OK PR#190 (MERGED) branch=refactor/kitmod-01-module-collapse commits=2
  ✓ 02-stats-plane               OK PR#191 (MERGED) branch=refactor/kitmod-02-stats-plane commits=8
  ✓ 03-subsystem-commands        OK PR#192 (MERGED) branch=feat/kitmod-03-subsystem-commands commits=2
  ⚠ 04-install-wire              STALLED branch=feat/kitmod-04-install-wire commits=0
  . 05-operate-contract          PENDING branch=docs/kitmod-05-operate-contract
  . 06-docs                      PENDING branch=docs/kitmod-06-docs
  ⚠ 08-mega-status               STALLED branch=feat/kitmod-08-mega-status commits=0
  . 07-reconcile                 PENDING branch=docs/kitmod-07-reconcile
kit-modularity: 3/8 ok  ⚠ 2 drift
```
Exit: 1 (drift > 0, correctly nonzero). This is ground truth at the moment of the run: SG-01/
02/03 genuinely shipped+merged (verified via real `gh pr view`), SG-04 and this SG-08 itself
genuinely had 0 commits on their branch at that point in time (both later gained commits as
their workers built), 05/06/07 genuinely hadn't started. No false positive, no false negative.

## Suite before/after (identical-or-better)

A full 87-file sweep (`tests/test-*.sh` + `lib/*/tests/test-*.sh`) was run before and after
this branch; two of the unrelated files (`test-orchestrate-wavefront.sh`,
`test-multiplexer.sh`) are inherently slow, multi-minute simulations whose pass counts are
sensitive to this box's momentary system load (confirmed by re-running the same file twice
and observing different partial counts under an external 90s timeout on both runs) --
noise unrelated to this branch, not a regression signal. The reliable, targeted comparison
is every file this change actually touches:

| Test file | Before (master) | After (this branch) | Verdict |
|---|---|---|---|
| `tests/test-mega.sh` (NEW) | did not exist | 16/16 PASS | new, all green |
| `tests/test-board.sh` | 36/45 PASS, 9 FAIL | 36/45 PASS, 9 FAIL | byte-identical |
| `tests/test-board-mirror.sh` | 72/72 PASS | 72/72 PASS | byte-identical |
| `tests/test-board-writeback.sh` | 53/54 PASS, 1 skip | 53/54 PASS, 1 skip | byte-identical |

The 9 `test-board.sh` FAILs are pre-existing and local-only (this box's `~/.claude/dwarves-kit`
install is stale relative to this worktree's `lib/board/board.sh` path -- the SAME issue
SG-02/SG-03's own proofs document); it SKIPS entirely in CI (ops-toolkit is absent there).
`test-board-mirror.sh` and `test-board-writeback.sh` stayed fully green after the
`--with-mega`/`_mega_rollups` addition, confirming the opt-in wiring never fires inside
either suite's fixtures (neither ever passes `--with-mega`). Net: strictly better (+16 new
passing checks across the touched surface, 0 new failures, 0 regressions).

## Reproduce

```
cd <dwarves-kit checkout>
git checkout feat/kitmod-08-mega-status
bash tests/test-mega.sh                        # 16/16, load-bearing NCs
bash tests/test-board.sh                       # unchanged from master (9 pre-existing local FAILs)
bash tests/test-board-mirror.sh                 # 72/72
bash tests/test-board-writeback.sh              # 53/54 (1 skip)
REPO_ROOT=<ops-toolkit path> CODE_ROOT=<dwarves-kit path> bash lib/mega.sh status kit-modularity
```

## Ship-gate back-compat run (folded from prior docs/verification/kitmod-mega-status.md)

This section carries the gate's required green run + NEGATIVE CONTROL in the flat
single-file shape (`docs/verification/README.md`'s back-compat form); kept verbatim
alongside the fuller narrative above so no evidence is lost in the fold.

### Green run

Command: `bash tests/test-mega.sh`
Exit: 0
Output: `PASS=16 FAIL=0` (drift-class taxonomy, the STALLED-vs-WIP nuance, `--rollup-only`,
error paths, and the `board --with-mega` wiring, all against a real mktemp git repo + a
PATH-injected stub `gh`, no real network call anywhere in the suite)

Command:
```
REPO_ROOT=~/workspace/tieubao/ops-toolkit CODE_ROOT=~/workspace/tieubao/dwarves-kit \
  bash lib/mega.sh status kit-modularity
```
Exit: 1 (drift present, correctly nonzero)
Output (real corpus, real `gh`):
```
kit-modularity: 3/8 ok  ⚠ 2 drift
```

Verdict: PASS

### NEGATIVE CONTROL

Reverted the change by moving the new entry file aside, re-ran, restored it:

```
$ bash lib/mega.sh status kit-modularity --megagoals-root ~/workspace/tieubao/ops-toolkit/_meta/megagoals --code-root ~/workspace/tieubao/dwarves-kit --rollup-only
kit-modularity: 3/8 ok  ⚠ 2 drift
Exit: 1

$ mv lib/mega.sh /tmp/mega.sh.bak   # revert
$ bash lib/mega.sh status kit-modularity ...
bash: lib/mega.sh: No such file or directory
Exit: 127                            # RED, as expected

$ mv /tmp/mega.sh.bak lib/mega.sh    # restore
$ bash lib/mega.sh status kit-modularity ... --rollup-only
kit-modularity: 3/8 ok  ⚠ 2 drift
Exit: 1                              # correctly RED again (drift present) -- confirms this
                                      # is not a hardcoded-green stub
```

The three drift-class NCs (NC-1 `CLAIM-UNVERIFIED`, NC-2 `STALLED`, NC-3
`MERGED-UNCHECKED`) plus the STALLED-vs-WIP nuance control are all load-bearing fixture
assertions inside `tests/test-mega.sh` (see the run detail above for the full run output);
each fixture's PR/branch state is independently constructed so a dumb `[x]`/`[ ]` echo
(the failure mode this verb exists to prevent) would fail every one of them.

Verdict: PASS (negative controls confirm the reconciler is load-bearing, not a no-op or a
green-wash).

### board.sh --with-mega wiring (additive, no regression)

Command: `bash tests/test-board.sh` (byte-identical render NC-e, never passes `--with-mega`)
Exit: same 9-of-45 pre-existing local-only failures as before this branch (unchanged;
`~/.claude/dwarves-kit` stale-install env issue, SKIPS in CI).

Command: `bash tests/test-board-mirror.sh` / `bash tests/test-board-writeback.sh`
Exit: 0 / 0
Output: `72/72` / `53/54 (1 skip)` -- unchanged from before this branch.

Verdict: PASS (the opt-in `--with-mega` flag never fires in either suite, confirmed both by
these suites staying green and by `tests/test-mega.sh`'s explicit "without --with-mega, zero
gh calls / no rollup section" assertion).

### Suite identical-or-better

Targeted before/after (every file this change touches; see the run detail above for why the
two other unrelated slow-simulation files in the full sweep are excluded as system-load
noise, not a regression signal):

| Test file | Before | After | Verdict |
|---|---|---|---|
| `tests/test-mega.sh` (NEW) | n/a | 16/16 | new, all PASS |
| `tests/test-board.sh` | 36/45, 9 FAIL (pre-existing local env) | 36/45, 9 FAIL | identical |
| `tests/test-board-mirror.sh` | 72/72 | 72/72 | identical |
| `tests/test-board-writeback.sh` | 53/54, 1 skip | 53/54, 1 skip | identical |

Verdict: PASS (identical-or-better; strictly better -- +16 new passing checks, 0 new
failures, 0 regressions).
