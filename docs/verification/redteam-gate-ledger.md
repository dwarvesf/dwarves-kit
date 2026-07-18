# Verification: rung-4 redteam gate ledger (cost checkpoint)

Closes the gap ops-toolkit's `research/2026-07-18-rung4-cost-checkpoint.md` found: real
rung-4 redteam rounds (in-harness adversarial skeptic, cap 3, verbatim `VERDICT: SECURE`)
had run inside hand-conducted megas, but none ever emitted a `redteam` `kit_gates` row, so
the ID-372 checkpoint ("tighten the rung-4 trigger if it averages >15% of mega cost") could
never be evaluated: N stayed 0 no matter how many redteams actually ran.

Two behavioral claims, both required:
1. A rung-4 round CAN NOW append a `redteam` `kit_gates` row carrying that round's token
   cost, in one call (`lib/gate/redteam-gate.sh round`).
2. That call brackets an `OUTCOME` start/end pair on the `redteam` phase, so `lib/stats`'
   `mega-durations` (no gate-name whitelist) picks the round up for free.

**Scope boundary (read before assuming N > 0 after this merges):** the redteam PROCEDURE
itself (the cap-3 loop, the `VERDICT: SECURE` judgment) lives in a sibling dotfiles repo's
SKILL.md blocks, out of scope for this PR. This PR makes the recording call cheap (one call
instead of three, kept in sync); it does not make anything call it. N stays 0 until the
dotfiles-side procedure is edited to call `start`/`round` at its own round boundaries --
that is a separate, tracked follow-up.

## What "done" means here

Two negative controls, both load-bearing:
- **NC1 (fail-closed emit):** a round with no `cost=` is rejected (rc 64) and writes NEITHER
  a `GATE` row NOR a `TOKENS` row NOR an `OUTCOME` end -- a failed-to-emit round is loud
  (the caller sees the rejection immediately) and leaves no fabricated ledger data, rather
  than silently landing as an untracked or zero-cost row a cost-checkpoint reader could
  mistake for a real, cheap round.
- **NC2 (honest-NULL, not fabricated-zero):** a malformed `TOKENS cost=` value, or a
  `redteam` `GATE` row with no phase-scoped `TOKENS` line at all, lands as `cost=NULL` in
  `kit_gates`, never a fabricated `0.0` that would silently understate the checkpoint's
  average.

Plus a FIFO-order proof: two rounds in one rid pair to their OWN cost (round 1 -> its cost,
round 2 -> its cost), never swapped, mirroring the exact FIFO-per-(rid,phase) contract
`OUTCOME` brackets already use (SPEC-129 DEC-002) -- this feature reuses that contract, it
does not invent a second one.

## Fixtures

Bash-level (`tests/test-redteam-gate.sh`): builds every ledger inline under a fresh
`DWARVES_KIT_LOG_DIR` per case (40 assertions across start/round, all 3 verdicts, the two
negative controls, multi-round FIFO, token-count passthrough, embedded-newline injection
defense, `gate.sh` dispatch, and usage errors).

Python-level (`lib/stats/tests/test-kit-gates-cost.sh`), a committed golden fixture at
`lib/stats/tests/fixtures/kit-gates-cost/runs/`:

| File (rid) | Contents |
|---|---|
| `rt-a.log` | 2 redteam rounds (findings cost=0.42, secure cost=0.31) + 1 unrelated `spec` gate |
| `rt-b.log` | 1 round, `TOKENS cost=notanumber` -- malformed input |
| `rt-c.log` | 1 round, no phase-scoped `TOKENS` line at all -- an orphaned/failed-then-retried round |
| `rt-d.log` | 1 round, plus an unscoped (no `phase=`) rid-wide `TOKENS` line that must never pair |
| `rt-e.log` | 1 round, `TOKENS cost=0` -- a real zero-cost round, must land `0.0` not `NULL` |

## Run 1: end-to-end round emit (bash, `tests/test-redteam-gate.sh`)

```bash
cd dwarves-kit
bash lib/gate/redteam-gate.sh start rt1
bash lib/gate/redteam-gate.sh round rt1 findings cost=0.42 round=1 in=1000 out=200 reason="2 findings, fixed"
bash lib/gate/redteam-gate.sh start rt1
bash lib/gate/redteam-gate.sh round rt1 secure cost=0.31 round=2
cat "$DWARVES_KIT_LOG_DIR/runs/rt1.log"
```

Result (verbatim, from a live run):
```
2026-07-18T10:03:05Z | OUTCOME | redteam | start | at=1784368985
2026-07-18T10:03:06Z | OUTCOME | redteam | end | at=1784368986 caught=true dur_s=1
2026-07-18T10:03:06Z | TOKENS | in=1000 out=200 cache_read=0 cache_create=0 cost=0.42 phase=redteam
2026-07-18T10:03:06Z | GATE | redteam | ran | round=1 verdict=findings 2 findings, fixed
2026-07-18T10:03:06Z | OUTCOME | redteam | start | at=1784368986
2026-07-18T10:03:08Z | OUTCOME | redteam | end | at=1784368988 caught=false dur_s=2
2026-07-18T10:03:08Z | TOKENS | in=0 out=0 cache_read=0 cache_create=0 cost=0.31 phase=redteam
2026-07-18T10:03:08Z | GATE | redteam | ran | round=2 verdict=secure
```

```bash
bash tests/test-redteam-gate.sh
```
Command: `bash tests/test-redteam-gate.sh`
Exit: 0
Result: `=== 40/40 passed, 0 failed ===`

## Rollback (negative control: revert -> RED -> restore)

Removed `cmd_round`'s cost-validation block (the single unified regex check that covers both
missing and malformed `cost=` -- see the code comment on why one check suffices), re-ran the
suite, confirmed RED, then restored from a pre-edit checkpoint copy and confirmed GREEN again,
byte-identical (`cmp` clean).

```bash
# remove the `if ! [[ "$cost" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then ...; fi` block from cmd_round
bash tests/test-redteam-gate.sh
```
Command: `bash tests/test-redteam-gate.sh` (with the validation block removed)
Exit: 1
Result (verbatim, RED):
```
FAIL AC6 missing cost= rejected (rc=0)
FAIL AC6 no GATE row written on a failed round
FAIL AC6 no TOKENS row written on a failed round
FAIL AC6 no OUTCOME end written on a failed round
FAIL AC6 exactly the one start line remains (got 4 lines)
FAIL AC13 malformed cost=1.2.3 rejected (rc=0)
FAIL AC13 malformed cost=1.2.3 wrote nothing
FAIL AC13 non-numeric cost=abc rejected (rc=0)

=== 32/40 passed, 8 failed ===
```
This is the exact regression NC1/AC13 exist to catch: with the check gone, a cost-less OR
malformed-cost round no longer errors, and instead silently writes a real
`GATE`/`TOKENS`(`cost=` empty or `1.2.3`)/`OUTCOME` triple -- precisely the "misleadingly
cheap zero-cost row" and "malformed-but-accepted cost" scenarios the design note warns
against.

```bash
cmp /tmp/redteam-gate-checkpoint.sh lib/gate/redteam-gate.sh   # byte-identical restore
bash tests/test-redteam-gate.sh
```
Command: `bash tests/test-redteam-gate.sh` (restored)
Exit: 0
Result: `=== 40/40 passed, 0 failed ===`

## Run 2 (NC1, load-bearing): a round with no cost= writes nothing

```bash
bash lib/gate/redteam-gate.sh start rt6
bash lib/gate/redteam-gate.sh round rt6 secure round=1   # no cost=
echo "rc=$?"
cat "$DWARVES_KIT_LOG_DIR/runs/rt6.log"
```

Result (verbatim):
```
redteam-gate.sh round: cost=<dollars> is required (a round with no captured cost cannot be ledgered; see file header)
rc=64
2026-07-18T10:03:22Z | OUTCOME | redteam | start | at=1784369002
```
Only the earlier `start` line survives; no `GATE`/`TOKENS`/`OUTCOME end` line was written.
The same rid can retry cleanly afterward (test AC6b).

## Run 3: `kit_gates` cost pairing + FIFO order + mega-durations pickup

```bash
cd lib/stats
export DWARVES_KIT_LOG_DIR="$(pwd)/tests/fixtures/kit-gates-cost"
uv run stats rebuild
uv run stats show kit_gates --json
uv run stats mega-durations --json
bash tests/test-kit-gates-cost.sh
```

Command: `bash tests/test-kit-gates-cost.sh`
Exit: 0
Result: `== 14 passed, 0 failed ==`. Key rows confirmed (verbatim from `show kit_gates --json`):
```json
{ "rid": "rt-a", "gate": "redteam", "reason": "round=1 verdict=findings 2 findings, fixed",
  "start_ts": "1000", "end_ts": "1030", "cost": 0.42 }
{ "rid": "rt-a", "gate": "redteam", "reason": "round=2 verdict=secure",
  "start_ts": "1030", "end_ts": "1050", "cost": 0.31 }
{ "rid": "rt-b", "gate": "redteam", "cost": null }   // malformed cost=notanumber
{ "rid": "rt-c", "gate": "redteam", "cost": null }   // no phase-scoped TOKENS line
{ "rid": "rt-d", "gate": "redteam", "cost": null }   // unscoped TOKENS line, never pairs
```
`mega-durations --json` includes `rt-a` (`wall_seconds: 50, n_gates_timed: 2`) with zero
changes to `mega-durations`'s own SQL -- it already has no gate-name whitelist.

## NC2 (honest-NULL, falsifiable, not vacuous)

```bash
uv run python3 -c "
from stats import materialize
print(materialize.query(\"SELECT count(*) FROM kit_gates WHERE gate='redteam' AND cost IS NULL\")[1][0][0])
"
```
Result: `3` (rt-b malformed + rt-c orphan + rt-d unscoped). If a future edit coerced an
unparseable/missing `cost=` to `0.0` instead of `NULL`, this count would silently drop to 0
and those rounds would join the checkpoint's average as fabricated free rounds. The inverse
falsifiable check (`rt-e`, `cost=0`) confirms a REAL zero is never swept into that NULL count
(`test-kit-gates-cost.sh`'s `C-zero` case).

## Review findings applied

Reviewed by `kit:code-reviewer` (architecture lens, 8/10 approve-with-suggestions),
`kit:code-reviewer` (test-coverage lens, 8/10 sufficient-with-gaps), and `kit:advisor`
(critique mode, fable model, sound-with-concerns). Applied before merge:

- **CI wiring gap** (architecture + test-coverage, independently): `lib/stats/tests/
  test-kit-gates-cost.sh` had no CI step (only its bash sibling did). Fixed: added
  `astral-sh/setup-uv` + a `uv sync` + test step to `.github/workflows/test.yml`, scoped to
  this one new test (the wider "no `lib/stats/tests/*.sh` runs in CI" gap is pre-existing
  across ~15 files and stays out of scope here).
- **Factually-inaccurate rationale comment** (fable): the header claimed a costless round
  "would desync the FIFO pairing" -- untrue, `read_kit_gates` already tolerates a missing/
  malformed cost by landing `NULL` in the queue slot, FIFO position preserved. Rewrote the
  rationale to the real reason: this tool exists to make rung-4 cost measurable, so silently
  allowing costless rounds would just relocate the checkpoint's original gap.
- **Overclaimed scope** (fable): the doc originally said rounds "now append" a `kit_gates`
  row; softened to "can now append", and added an explicit SCOPE note (both here and in the
  script header) that the dotfiles-side redteam PROCEDURE is not wired to call this yet --
  that adoption is a separate, tracked follow-up, not implied by this PR.
- **Lax cost validation** (fable): `cost=1.2.3` previously sanitized-then-silently-accepted
  (landing `NULL` downstream); tightened to one strict regex (`^[0-9]+(\.[0-9]+)?$`) that also
  subsumes the missing-cost case, so the separate presence check was removed as redundant.
  Covered by new AC13 (bash) + the `rt-e` fixture (Python side, `cost=0` is real and distinct
  from "malformed").
- **`cost=0` untested** (test-coverage): added AC13 (bash) and `rt-e`/`C-zero` (Python),
  confirming a real zero-cost round is never confused with the honest-NULL cases.
- **`main()`'s bare-usage arm untested** (test-coverage): added AC11b (no-args, `-h`,
  `--help`, `help`).
- **Stale cross-reference** (fable): `schemas.py`'s `cost` column comment pointed at an
  adapters.py docstring sentence this PR itself had already removed; fixed the pointer.
- **Fabricated-zero token counts vs honest-NULL cost** (fable): documented, not changed --
  `in=`/`out=`/etc. still zero-default (inherited from `gate-ledger.sh tokens()`, unlike
  `cost`), which is now a named asymmetry in the script header rather than a silent one.

Deferred, not applied (named as residual risk, not blockers): the redteam PROCEDURE's own
dotfiles-side wiring (cross-repo, explicitly out of scope for this PR); the narrow
between-subprocess-calls partial-write window (now named in the header comment); the
pre-existing double-`start`-with-no-`end` timestamp-corruption case in `read_kit_gates`
(inherited behavior, not introduced by this PR).

## Full suite, no regressions

```bash
bash tests/test-meta.sh
```
Command: `bash tests/test-meta.sh`
Exit: 0
Result: `Passed: 698 / 698` (pre-existing suite, run after every change above; every
pre-existing `lib/stats/tests/*.sh` and root `tests/test-gate-outcome.sh`,
`tests/test-quiz-gate.sh`, `tests/test-gate-vocab-recording.sh`,
`tests/test-outcome-emit-sweep.sh`, `tests/test-schema-parity.sh` re-run green, since the new
`cost` column is additive-only, see `lib/stats/src/stats/adapters.py::read_kit_gates`
docstring).

## Reproduce

```bash
git checkout feat/redteam-gate-ledger
bash tests/test-redteam-gate.sh
(cd lib/stats && uv sync && bash tests/test-kit-gates-cost.sh)
bash tests/test-meta.sh
bash tests/test-kit-contract.sh
```
The `uv sync` step is what `.github/workflows/test.yml`'s new CI step also runs (verified
locally against a freshly-rebuilt `.venv`, not just the pre-existing one).
