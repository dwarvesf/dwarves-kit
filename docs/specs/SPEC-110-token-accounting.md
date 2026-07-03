# SPEC-110: token accounting + efficiency metrics

Status: VALIDATED
Lane: full
Type: spec-feature

## Problem

The kit routes model tiers to save tokens (SPEC-087/107) but has NO token DATA: no run records how
many tokens it cost, so no metric can say whether cheap-first is working, which lane is expensive,
or whether caching helps. Token cost is invisible to the ledger + telemetry.

The mega-goal (roadmap: ops-toolkit `_meta/megagoals/kit-face/`, assumptions 03) resolves this with
a CAPTURE-GATED token record: runs already captured to stream-json (`--stream` /
`DETERMINISTIC_HANDOFF=1`) get a durable TOKENS ledger line + telemetry; the default `claude -p`
path is byte-unchanged (SPEC-087's sacred default-invocation pin) and honestly reports `usage=?`.

## Solution

1. **`gate-ledger.sh tokens <rid> in=N out=N cache_read=N cache_create=N [cost=N]`** , a new
   subcommand appending `<ts> | TOKENS | in=N out=N cache_read=N cache_create=N[ cost=N]` to the
   rid's ledger. Values sanitized to non-negative integers. It is an ADDITIVE MARKER: `check()`,
   the override guard, and `descent()` all filter on `$2=="GATE"` (verified gate-ledger.sh:186,
   154, 281), so a `| TOKENS |` line is invisible to gate enforcement , no risk of faking a gate.
   Single-writer append, same discipline as `record`/`action`.
2. **`handoff_gen.py sum-usage <stream.jsonl>`** , sums `usage.{input_tokens, output_tokens,
   cache_read_input_tokens, cache_creation_input_tokens}` across the transcript's assistant
   messages (the in-kit stream-json reader already parses these entries), prints
   `in=N out=N cache_read=N cache_create=N`. It sums ONLY assistant entries (`cc_compact._is_assistant`, `None`-guarded on `msg.get("usage")`); a real `--output-format stream-json` emits a final `type:"result"` event carrying CUMULATIVE usage that must NOT be re-summed (a result-line fixture is the negative control). Sidechain (`isSidechain:true`) entries are summed into the run total for v1 (run granularity), NOT separated per-round (see the probe + Not:).
3. **orchestrate.sh** , after `_run_one_session` returns on a CAPTURE path (`$_ROS_SLOG` non-empty:
   the `--stream`/`DETERMINISTIC_HANDOFF` branch), parse `$_ROS_SLOG` via `handoff_gen.py sum-usage`
   and call `gate-ledger.sh tokens <rid> ...`. rid derivation is factored into a SHARED helper `_rid_for <dir> <id>` that BOTH `_emit_start` and the token hook call, so the START line and the TOKENS line cannot drift into different `<rid>.log` files (spec-validate finding). The default (no-capture) path writes NO TOKENS line , the run's usage is honestly
   unknown, never a fake zero. The watchdog path stays a declared gap v1.
4. **`lane-telemetry.sh report`** , a token section: a SECOND awk pass over `$2=="TOKENS"` lines joined to the run's lane via the START line's rid->lane (NOT a `_rows` extension; `_rows` carries no token fields). Per lane, median tokens-to-done (in+out summed
   per run, median across runs carrying a TOKENS line), cache efficiency
   (`cache_read / (input + cache_read)`), and rework share at RUN granularity (tokens in bug/debug
   re-runs vs total). Runs with no TOKENS line report `usage=?` and are EXCLUDED from medians (never
   counted as zero). NO thresholds pinned , a "5-run baseline first" note instead (the SPEC-073
   pattern).
5. **`lane-telemetry.sh render --mermaid`** , a mermaid output mode. `render()` detects a leading `--mermaid`/`mermaid` as a MODE arg BEFORE its existing substring-filter positional (so the ASCII `render [filter]` path stays byte-compatible), annotating
   each lane node with its median tokens-to-done (per lane/per run, NOT per-phase , usage is
   per-session). The existing ASCII render is unchanged (additive mode).
6. **Sidechain-usage probe (one run)** , inspect a real/seed stream-json for `isSidechain:true`
   entries and whether their `usage` is attributable to a round; record the finding
   (docs/verification). It informs whether per-round rework share is ever measurable; v1 answer
   feeds the run-granularity decision.

Additive-marker convention sentence (shared verbatim with SPEC-108's `generated-by:` discipline):
*a new record line uses a distinct `$2` marker so the existing single-`$2`-keyed readers ignore it
by construction; one line per call; values sanitized.*

## Verification

```bash
cd dwarves-kit
# 1. gate-ledger tokens subcommand writes a TOKENS line; check() ignores it (not a gate):
bash tests/test-ledger-durability.sh   # + the SPEC-110 tokens block (write + check-ignores-it NC)
# 2. handoff_gen sum-usage sums the seed transcript's usage:
python3 lib/handoff/handoff_gen.py sum-usage tests/fixtures/handoff-det/seed.jsonl   # in=.. out=.. cache_read=.. cache_create=..
# 3. orchestrate CAPTURE path calls gate-ledger tokens (mock CLAUDE_CMD real run -> TOKENS line);
#    NC: the default no-capture path writes NO TOKENS line (usage=?):
bash tests/test-orchestrate.sh         # + the SPEC-110 capture-path token block + the no-capture NC
# 4. lane-telemetry report token section + usage=? honest null + render --mermaid annotation:
bash tests/test-lane-telemetry.sh      # + the SPEC-110 token-section + usage=? NC + mermaid-annotation block
```

## After state

- `lib/gate-ledger.sh`: `tokens` subcommand (TOKENS marker, sanitized, gate-invisible).
- `lib/handoff/handoff_gen.py`: `sum-usage` CLI + a `sum_usage()` function.
- `lib/orchestrate.sh`: capture-path post-session token extraction -> `gate-ledger tokens`; default
  path unchanged (SPEC-087 pin intact); watchdog path a declared gap.
- `lib/lane-telemetry.sh`: `report` token section (median tokens-to-done/lane, cache efficiency,
  run-granularity rework share, `usage=?` honest nulls); `render --mermaid` per-lane annotation.
- tests extended: ledger-durability (tokens subcommand + gate-invisible NC), orchestrate
  (capture-path TOKENS + no-capture `usage=?` NC), lane-telemetry (token section + `usage=?` NC +
  mermaid annotation).
- `docs/verification/token-accounting.md`: run-table incl. the captured mock-run TOKENS line, the
  `usage=?` NC, and the sidechain probe finding.

## Scope edges

**In:** the tokens subcommand, sum-usage parser, orchestrate capture-path extraction, lane-telemetry
report token section + render mermaid annotation, the tests, the probe.
**Out:** flipping the default path to json (SPEC-087 pin, SACRED); watchdog-path capture (declared
gap); transcript-joins for manual runs; threshold pinning (5-run baseline first).
**Not:** per-phase token attribution (impossible , usage is per-session; say so, do not fake it); a
cost dashboard beyond the render annotation; pricing tables.

## Open questions

The "real captured orchestrate run" proof uses the kit's standard MOCK `CLAUDE_CMD` (test-orchestrate
harness) emitting a stream-json with the seed's usage shape , this exercises the REAL orchestrate ->
sum-usage -> gate-ledger-tokens PATH (the wiring the gate demands), deterministically and
reproducibly, without a nondeterministic/expensive live LLM call. The seed fixture's usage numbers
are real-shape (`cache_read_input_tokens` etc. exactly as `claude --output-format stream-json`
emits). Rework share is RUN-granularity v1 because the sidechain probe (item 6) determines whether
per-round separation is even possible; if the probe shows sidechain usage is attributable, per-round
is a filed follow-up.
