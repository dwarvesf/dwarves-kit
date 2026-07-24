---
name: observe
description: Query and render the kit's control plane from an agent session. Use when asked about the fleet's runs, gate verdicts, conformance, spend/tokens/cache economics, the cognitive-debt score, replaying a recorded run, benchmark results, or building/refreshing the observability dashboard. Trigger phrases include "dashboard", "control plane", "how much did we spend", "token usage", "cache hit rate", "cognitive debt", "debt score", "replay run <rid>", "gate log for <rid>", "conformance", "fleet stats", "observability numbers". All surfaces are CLIs under lib/bench; agents should prefer the JSON verbs over parsing HTML.
---

# observe , the control plane from an agent session

Every observability surface is a stdlib-only CLI in `lib/bench/` (resolve the kit root via
`$DWARVES_KIT` or this skill's own location). Prefer JSON verbs; render HTML only when a
human will look at it.

## Query numbers (agent surface, JSON)

```sh
python3 lib/bench/dashboard.py stats            # fleet + money + debt + alerts, one blob
python3 lib/bench/dashboard.py debt --format json   # cognitive-debt score alone (ADR-0031)
```

`stats` keys: `fleet` (runs, gate counts, override/misfire rates, conformance),
`money` (computed spend, token mix, cache-hit, per-model), `debt` (score, open defers,
last paydown), `alerts` (rule id + firing). Money is COMPUTED from list prices, an
estimate, not an invoice; say so when reporting spend.

## Replay and inspect runs

```sh
python3 lib/bench/tui.py run <rid>          # terminal replay of a recorded run,
                                            # expected-vs-actual conformance overlay
python3 lib/bench/tui.py demo               # interaction demo, no model calls
bash lib/telemetry/lane-telemetry.sh trace <rid>   # the text run report
```

## Render pages (human surface)

```sh
python3 lib/bench/dashboard.py build --out dashboard.html   # full control plane
python3 lib/bench/report.py build --rids r1,r2 --out report.html   # one mega-run
python3 lib/bench/viewer.py build --ledger name=<rid> --out viewer.html  # diagram player
```

The dashboard's Config & tool policy section renders `kit.toml` and the tool-choice
policy; the enforcement half is `hooks/tool-policy-guard.sh` reading
`~/.claude/dwarves-kit/tool-policy.json`.

## Benchmarks

```sh
python3 lib/bench/bench.py run --suite lib/bench/suites/smoke-code --models haiku,sonnet
python3 lib/bench/bench.py diff --baseline old.jsonl --candidate new.jsonl  # exit 1 on regression
```

## Rules

- Costs are estimates from a price table; never present them as billing truth.
- Transcript-derived data is counts-only (tool names, tokens, timing), never content.
- The debt score pressures the weekend paydown; do not treat it as a blocker.
