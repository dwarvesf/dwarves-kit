# Implementation notes -- lane-de-escalation

Delta from `docs/specs/SPEC-141-lane-de-escalation.md`. The spec pins the chosen shape,
the floor default, and the ledger line format; this logs decisions the spec's prose left
implicit at build time and one deliberate deviation from an existing sibling pattern.

## 2026-07-04 Diff-size sum is a 2-source union, NOT the 3-source union coverage-delta.sh/proof-ledger.sh use
- Context: `lib/gate/coverage-delta.sh` and `lib/gate/proof-ledger.sh` both sum THREE `git diff --numstat`
  sources per file (`base..HEAD`, `diff HEAD` (working tree), `diff --cached` (staged)) and add
  all three. Tracing it: `git diff HEAD` already reflects the FULL working tree vs `HEAD`
  (staged + unstaged combined), so `--cached` is a subset of it, not an additional delta --
  the existing pattern double-counts every staged-but-uncommitted line.
- Decision: `_deesc_changed_lines` sums only two sources -- `base..HEAD` (committed range) +
  `diff HEAD` (working tree, staged already folded in). No `--cached` term.
- Why: the two existing gates' double-count is harmless for THEM (more counted lines biases
  them toward MORE warnings, which is their safe/advisory direction: coverage-delta wants to
  err toward flagging under-tested diffs). This gate's bias runs the OTHER way: over-counting
  lines here makes a genuinely-small diff look bigger, i.e. it would UNDER-nudge, defeating the
  sub-goal's entire purpose. Correctness, not just tidiness, required breaking from the sibling
  pattern here.
- Alternatives considered: copy the 3-source union verbatim for consistency with `coverage-
  delta.sh` (rejected -- wrong bias direction, see above); shell out to `coverage-delta.sh`'s
  own helpers directly (rejected -- would couple a lane-classify.sh verb to a different `lib/`
  script's internals for no shared behavior, since the classification-by-file-type logic
  coverage-delta.sh also carries is irrelevant here, this gate only wants a total line count).
- Impact: at the real call site (`commands/ship.md` Step 8, right before `git push`), the
  branch is already fully committed (Steps 6/7 ran), so in practice this collapses to
  `base..HEAD` alone; the working-tree term only matters for a `deescalate` invocation run
  before the final commit (e.g. manual testing).

## 2026-07-04 `deescalate` lives in `lib/classify/lane-classify.sh`, not a new `lib/lane-deescalate.sh`
- Context: the mega-goal framing suggested "a small `lib/` change"; a fresh file (mirroring
  `lib/gate/coverage-delta.sh`'s own standalone shape) was the alternative on the table.
- Decision: added as a new verb on the EXISTING `lib/classify/lane-classify.sh`, alongside `escalate()`.
- Why: `escalate()` (SPEC-094, text-based, up-only, spec->build boundary) and `deescalate()`
  (SPEC-141, size-based, down-only, ship boundary) are explicitly framed as the two halves of
  "escalation is not one-way" -- keeping them in the same file means `lane_rank`'s tiny/bug/
  backfill-never-fire guard is written and owned in exactly one place, not duplicated across
  two files that both need to know the lane hierarchy.
- Impact: `lib/classify/lane-classify.sh` gained a `GATE_LEDGER` path var (used only by `deescalate`'s
  ledger write); every other verb in the file is unaffected and untested-for-regression (the
  existing `tests/test-lane-classify.sh` + `tests/test-lane-escalation.sh` both still pass
  unchanged, confirmed as part of this sub-goal's verification run).

## 2026-07-04 Ledger write uses the existing `action` verb, not a new gate-ledger subcommand
- Context: `gate-ledger.sh` already has `record`, `debt`, `debt-response`, `tokens`, `outcome`,
  and `action` as distinct additive marker verbs; a case could be made for a dedicated
  `deescalate`-flavored marker (mirroring how `debt`/`debt-response` got their own verb pair).
- Decision: reused `action <rid> <text>` verbatim, encoding the four data fields
  (`chosen=`/`lines=`/`floor=`/`verdict=`) as space-separated `key=value` tokens inside the
  free-text argument (mirrors `significance-classify.sh`'s `debt` line shape).
- Why: this is a ONE-SHOT advisory data point, not a phase gate with a required/skipped state
  (`check()`/`required()`/`descent()` have no reason to ever know about it) -- exactly what
  `action` has existed for since ADR-0024's original ledger design, and a new subcommand would
  duplicate that with no behavioral difference.
- Impact: a future `lib/telemetry/lane-telemetry.sh` misroute-aggregation reader can `grep '| ACTION |
  lane-deescalate'` and parse the four `key=value` tokens directly; not built in this sub-goal
  (out of scope, named in the spec).

## No deviations beyond the three entries above; SPEC-141 acceptance criteria 1-7 implemented verbatim.
