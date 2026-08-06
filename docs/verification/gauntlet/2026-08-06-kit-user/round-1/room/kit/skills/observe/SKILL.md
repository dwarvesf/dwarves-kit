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
python3 lib/bench/dashboard.py stats                 # fleet + money + debt + alerts, one blob
python3 lib/bench/dashboard.py debt --format json    # cognitive-debt score alone (ADR-0031)
python3 lib/bench/dashboard.py allocation --period week --budget N --format json
```

`allocation` answers the lead's question: where the pool went (member → feature, feature =
git branch), period over period, plus a proposed next-period allowance plan.
`--format md` emits the weekly/monthly report as paste-ready markdown.

`stats` keys: `fleet` (runs, gate counts, override/misfire rates, conformance),
`money` (computed spend, token mix, cache-hit, per-model), `debt` (score, open defers,
last paydown), `alerts` (rule id + firing). Money is COMPUTED from list prices, an
estimate, not an invoice; say so when reporting spend.

## Replay and inspect runs

The run TUI is a forge product (`forge/cli/forge-tui`), standalone stdlib, and it
mirrors the agent verbs so a terminal session needs nothing from this repo:

```sh
forge-tui runs --format json [--repo R] [--lane L] [--misfires] [--low-conformance]
forge-tui debt --format json                # same ADR-0031 score as the web
forge-tui stats --format json               # fleet numbers
forge-tui run <rid>                         # replay with the conformance overlay
bash lib/telemetry/lane-telemetry.sh trace <rid>   # the text run report
```

Set `DWARVES_KIT_ROOT` so lane plans resolve (that turns on conformance numbers).
Spend and the efficiency ranking are kit-side only, one price table: use
`dashboard.py stats` for money.

## Render pages (human surface)

```sh
python3 lib/bench/dashboard.py export --out sections.json  # fleet payload for the forge SPA
#   --repos a,b = TEAM scope (hard allowlist, filtered before any metric);
#   default is personal scope (everything on this host)
#   (the dashboard PAGE is forge site/dashboard/; add --push <api> for connected mode)
python3 lib/bench/dashboard.py session <rid> --out s.html    # one session log, shareable
python3 lib/bench/dashboard.py sessions --out-dir sessions/  # all of them + index
python3 lib/bench/dashboard.py transcript <id> --out t.html  # FULL transcript (opt-in)
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
- The efficiency ranking measures token economics, not value delivered; never
  report it as a performance judgement, and respect its volume floor.
- Share a specific run as `<dashboard-url>#run/<rid>` (deep link) or link its standalone
  page at `sessions/<rid>.html`.
- `transcript` reads message CONTENT and is opt-in per invocation; every string passes a
  redaction mask that can miss. Never commit a real transcript to a public tree, and never
  paste one outside the team without reading it first.
- Allocation plans are proposals. Export them; do not describe them as applied.
