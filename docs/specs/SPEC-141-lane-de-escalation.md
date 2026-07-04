# Spec: Ship-time lane de-escalation nudge (kit-run-integrity sub-goal 07, ID-257 kit half)

Generated: 2026-07-04
Status: DRAFT
Lane: normal (one advisory verb added to an existing `lib/` script + one `commands/ship.md`
bullet + one `WORKFLOW.md` doc line + an over-test suite; ADVISORY by hard contract -- it
never blocks, never re-classifies, never cuts a gate -- so it does not earn the full lane
despite touching `lib/`, the same reasoning SPEC-130/coverage-delta and SPEC-140/pitch used).

## Problem

Escalation in this kit is currently one-way. `lib/lane-classify.sh check` (SPEC-053) warns at
INTAKE when the chosen lane is lighter than the text implies; `lib/lane-classify.sh escalate`
(SPEC-094) warns at the SPEC->BUILD boundary when the spec's own text implies a heavier lane
than the one recorded. Both only ever push UP ("size up or say why"); `lane_rank`'s own
comment says it plainly: "Under-sizing is the only dangerous direction; over-sizing is always
safe." That is true for correctness, but it leaves a blind spot for CALIBRATION: a run that
took the `normal` or `full` lane (extra ceremony: `/spec`, `/review`, `/docs`, `/ship`'s
gate-record) and then shipped a diff of a handful of lines never gets told so. The kit's own
misroute telemetry (`lib/lane-telemetry.sh misfires`) only sees TEXT-vs-CHOSEN mismatches
recorded at intake; it has zero data on the DIFF-SIZE-vs-CHOSEN mismatch, because nothing
measures the diff at ship time and nothing writes it to the ledger.

## Solution

### Approaches considered

1. **A new `deescalate` verb on `lib/lane-classify.sh`, sized off `base..HEAD` diff lines,
   fired from `commands/ship.md` Step 8. CHOSEN.** Mirrors `escalate()`'s shape exactly (same
   file, same "compare chosen lane against a computed suggestion" idea, just the opposite
   direction and a size signal instead of a text signal), so the two live side by side as the
   two halves of "escalation is not one-way." Reuses the `hooks/ship-gate.sh` / `lib/coverage-
   delta.sh` base-resolution convention (`origin/HEAD` symref -> `main`/`master` fallback) so
   there is no second copy of that logic. ADVISORY: prints one line, never blocks, and appends
   one `gate-ledger.sh action` line (an existing verb, unchanged) so the observatory's misroute
   query has real data to read.
2. **A new standalone `lib/lane-deescalate.sh` script.** Rejected: the whole point is that this
   is `escalate()`'s dual, not a new concept; a second file would duplicate the lane-rank logic
   `lane-classify.sh` already owns (tiny/bug/backfill never fire, normal/full can) and split the
   "which direction can this lane move" story across two files for no benefit.
3. **A live diff-size classifier feeding `lib/lane-classify.sh check`'s existing warn+log
   path** (i.e., extend the INTAKE floor check to also consider diff size). Rejected: `check`
   runs at intake, before any diff exists; there is nothing to size yet. The signal this sub-
   goal needs is only available at ship time, after the diff is final.
4. **A push-blocking gate ("diff too small for this lane, re-file it").** Rejected outright,
   named explicitly in the mega-goal's contract: "Advisory ONLY -- never blocks, NO gate cuts,
   NO verdict, NO numbers-that-block (this CREATES the misroute numbers, per Han's rule)." A
   block here would also be actively harmful: a `normal`/`full` lane chosen for a SMALL diff is
   never wrong on its own (a one-line auth change is still `full`); the nudge is a "consider
   next time" signal for the OPERATOR's classification habit, never a claim that THIS ship was
   mis-sized.

### Chosen shape

`lib/lane-classify.sh deescalate <chosen-lane> [--rid <rid>] [--root <path>] [--base <ref>]
[--floor <N>]`, invoked from `commands/ship.md` Step 8 (after the SPEC-136 significance record
+ SPEC-140 pitch offer, both already there). It:

1. Returns silently (exit 0, no output) for `tiny`/`bug`/`backfill` -- only an escalated lane
   (`normal`/`full`) can ever be found "too heavy after all"; nothing here ever calls a bug or
   backfill run oversized, mirroring `lane_rank`'s "over-sizing is always safe" stance.
2. Resolves the shipped diff's size: `base..HEAD` (mirrors `hooks/ship-gate.sh`'s
   `_resolve_base` / `lib/coverage-delta.sh`'s `_resolve_base`: `origin/HEAD` symref, else
   `origin/main`/`main`/`origin/master`/`master`) PLUS any uncommitted working-tree delta
   (`git diff HEAD`), summed via `git diff --numstat` added+deleted lines.
3. Compares the total against `LANE_DEESCALATE_FLOOR` (env var, default **20**; see "Design" for
   the rationale). Under the floor: prints the advisory nudge line and, when `--rid` is given,
   appends one `gate-ledger.sh action <rid> "lane-deescalate chosen=<lane> lines=<N>
   floor=<F> verdict=misroute-tiny"` line (an EXISTING verb, unchanged -- `action` has shipped
   since ADR-0024). At or over the floor: silent, no ledger write. ALWAYS returns 0 either way.

## Design

### Why `base..HEAD` + working-tree, not the 3-way union `coverage-delta.sh`/`proof-ledger.sh`
use

`lib/coverage-delta.sh` and `lib/proof-ledger.sh` sum THREE diff sources per file
(`base..HEAD`, `diff HEAD` (working tree), `diff --cached` (staged)) and add all three
together. That triple sum silently double-counts: `git diff HEAD` (working tree vs `HEAD`)
already folds in the staged delta (`--cached` is a SUBSET of it, not an additional one), so
adding `--cached` again on top over-counts every staged-but-uncommitted line by 2x. It is
harmless for those two gates (more counted lines biases them toward MORE warnings, which is
their safe direction), but this gate's bias runs the OTHER way: over-counting lines here makes
a genuinely-small diff look bigger, i.e. UNDER-nudges. `deescalate()` therefore sums only
`base..HEAD` (the committed range) + `diff HEAD` (working tree, staged already included) --
two sources, no double count. At the real call site (`commands/ship.md` Step 8, right before
`git push`), the branch is fully committed anyway (Steps 6/7 already ran), so in practice this
is `base..HEAD` alone; the working-tree term only matters for a dry-run invocation before the
final commit.

### The floor: `LANE_DEESCALATE_FLOOR`, default 20

One tunable, named, overridable (env var, not a magic number baked into the script). Rationale
for **20**: the lane table's own `tiny` definition is "typo, copy, comment, one obvious edit" --
a single edit rarely exceeds a handful of changed lines. 20 changed (added+deleted) lines is
loose enough that a real one-file bug tweak or a short doc fix does not spuriously nudge
(avoiding the fatigue the anti-fatigue guards elsewhere in this kit are built to prevent), but
tight enough to catch the case this sub-goal exists for: a `normal`/`full` lane chosen for
what turned out to be a copy-edit-sized diff. Raise it (e.g. 50) to nudge less often; lower it
to nudge more. Documented next to the Lane×phase depth matrix in `WORKFLOW.md`, not just in
this spec, since that is where an operator tuning lane behavior already looks.

### The ledger line format

`TS | ACTION | lane-deescalate chosen=<lane> lines=<N> floor=<F> verdict=misroute-tiny` --
space-separated `key=value` tokens (mirrors `significance-classify.sh`'s `debt` line shape:
`significance=... worthiness=... verdict=...`), so a future observatory query can `grep '|
ACTION | lane-deescalate'` and parse the four fields without a new log format. The `ACTION`
marker (not a new `| GATE |` phase) is deliberate: this is not a phase gate with a required/
skipped state, it is a one-shot advisory data point, exactly what `action <rid> <text>` has
existed for since ADR-0024's original ledger design.

### No-block guarantee

`deescalate()` uses `return 0` on every path (silent-no-fire, nudge-fires, and the two guard
paths: unresolvable base, non-numeric diff count). The `gate-ledger.sh action` call inside is
wrapped `|| true`, so even a ledger-write failure cannot fail the calling command. `commands/
ship.md` invokes it as a bare `bash lib/lane-classify.sh deescalate ...` step with no `&&`/exit-
code check gating the push that follows, the same wiring shape as the SPEC-125 ★-tap nudge and
the SPEC-140 pitch offer immediately above it in Step 8.

## Acceptance criteria

1. **Fire, normal lane + tiny diff:** `deescalate normal --floor <F>` against a diff under `F`
   changed lines prints the advisory nudge line naming the lane and the line count.
2. **Fire also appends the ledger line:** with `--rid <rid>`, the fire case also writes exactly
   one `| ACTION | lane-deescalate chosen=normal ... verdict=misroute-tiny` line to that rid's
   ledger.
3. **No-fire, large diff (the false-positive negative control, load-bearing):** `deescalate
   normal --floor <F>` against a diff at or over `F` changed lines prints NOTHING and writes NO
   ledger line.
4. **No-fire, tiny/bug/backfill lane:** even a 1-line diff never fires for `tiny`, `bug`, or
   `backfill` -- only `normal`/`full` can ever be flagged.
5. **NO-BLOCK NEGATIVE CONTROL (load-bearing, absolute):** the fire case's exit code is 0. A
   ledger-write failure (e.g. an unwritable log dir) still leaves the command's own exit at 0.
6. **`WORKFLOW.md` documents the floor** next to the Lane×phase depth matrix: the tunable name,
   its default, and that it is overridable.
7. **`commands/ship.md` Step 8 wires the call** after the existing SPEC-136/SPEC-140 bullets,
   documented as advisory-only, never-blocks.

## Verification

```
# Acceptance 1-5 (fire / ledger-append / no-fire NC / lane-guard / no-block NC):
bash tests/test-lane-deescalate.sh

# CI-portability check: the suite must pass with NO local ledger state present (a prior
# sub-goal's CI failure came from a test rendering against machine-local
# ~/.local/state/dwarves-kit ledger data absent in a fresh CI checkout):
env HOME="$(mktemp -d)" bash tests/test-lane-deescalate.sh

# No regression in the existing lane-classify / structural suites:
bash tests/test-lane-classify.sh
bash tests/test-lane-escalation.sh
bash tests/test-meta.sh 2>&1 | tail -5
```

## Test plan

| # | Category | Case | Asserts |
|---|---|---|---|
| T1 | Happy path / fire | normal lane, diff < floor | advisory line printed, names lane + line count (AC1) |
| T2 | Ledger append | fire case with `--rid` | one `\| ACTION \| lane-deescalate ...verdict=misroute-tiny` line (AC2) |
| T3 | FALSE-POSITIVE NC (load-bearing) | normal lane, diff >= floor | NOTHING printed, no ledger line (AC3) |
| T4 | Lane guard | `tiny`/`bug`/`backfill` lane, tiny diff | never fires regardless of size (AC4) |
| T5 | NO-BLOCK NC (load-bearing, absolute) | fire case, capture `$?` | exit 0 (AC5) |
| T6 | NO-BLOCK NC, ledger-write failure | fire case with an unwritable `--rid` ledger dir | still exit 0 (AC5) |
| T7 | full lane also fires | `full` lane, diff < floor | fires same as normal (AC1/AC4 boundary) |
| T8 | Floor is overridable | same diff, two different `--floor` values | fires under the tight floor, silent under the loose one |
| T9 | Doc wiring | `WORKFLOW.md` / `commands/ship.md` grep checks | floor + default + wiring documented (AC6, AC7) |

## Out of scope

- `lane-classify.sh`'s text-based `check`/`escalate` heuristics (unchanged).
- The lane matrix cells themselves, and any escalation-UP logic (SPEC-053/SPEC-094 unchanged).
- The skill-side decompose rule (that rode a separate sub-goal in `tieubao/dotfiles`).
- Auto-reclassification of a shipped run, or any block/gate-cut based on diff size.
- Promoting this from advisory to a hard signal (`lib/lane-telemetry.sh` consuming the new
  `ACTION` line into an aggregate report is a natural follow-up, not built here).
