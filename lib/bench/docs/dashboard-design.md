# Control-plane dashboard: design

Backfilled design record for `dashboard.py` (operator direction 2026-07-25: "clone them
all, every feature and render, using our session data... apply the kit... backfill
design docs"). Feature source: `docs/research/2026-07-25-fiddler-control-plane-features.md`
(blog + screenshots + docs-index scan). Consuming rows: ID-425 (+ ID-424 replay).

## Surface map (ours ↔ data source ↔ Fiddler analogue)

| Sidebar surface | Data source (all real) | Fiddler analogue | Notes |
|---|---|---|---|
| Fleet | every `logs/runs/*.log` ledger, 30-day window | fleet intelligence KPIs + trends | tiles + SVG sparklines (runs/day, gate records/day); no hand-entered numbers |
| Run explorer | same ledgers + `gate-ledger.sh plan` per lane | Trace Explorer + Segments | filter box + segment chips (misfires, low-conformance, lanes, last-7d); per-row conformance chip; replay command per rid |
| Event stream | every GATE line, time-ordered | live event stream w/ verdict chips | OK / SKIP / OVERRIDE chips + full reason on hover |
| Tool activity | Claude Code transcripts (`~/.claude/projects`) | MCP-and-PR activity, "every tool call" | COUNTS ONLY (see privacy rule); top tools, MCP servers seen, per-session table |
| Bench / RCA | `runs/*.jsonl` bench rows | RCA events table | headline KPIs + the failure-fingerprint table (verbatim failing case) |
| Alerts | metrics + plain JSON rules | template-based alerts | evaluated at BUILD time, propose-first, no daemon |

Not cloned, deliberately (defer-don't-own, N4): gateway inline enforcement (<100ms
allow/block/redact path), the NLP enrichment/metric zoo, embedding 3D viz, RBAC and
compliance certifications (ID-414/417 enterprise territory). Our secret-guard hooks
already give harness-plane enforcement; a future verdict join, not a gateway build.

## Privacy rule (binding)

The transcript scan aggregates tool NAMES, model ids, and timestamps only. Message
content, prompts, file paths, and tool arguments are never read into the page.
Enforced by test `test_sessions_counts_only` (a planted content string must not
appear in output).

## Alert rule schema (plain files, template-based)

```json
{"id": "override-rate", "metric": "override_rate", "op": ">", "threshold": 0.15,
 "severity": "warn", "note": "..."}
```

Metrics available: runs, repos, gate_records, ran, skipped, overridden,
override_rate, skip_rate, misfires, misfire_rate, full_conformance, conf_known.
Default rules ship in code (`DEFAULT_ALERTS`) and as `examples/alerts.json`;
`--alerts FILE` overrides. Evaluation is at build time by design (N6
propose-never-dispose; a live alerting daemon is a separately-argued step).

## Decisions

1. **Static single-file page, sidebar as tabs.** No server, no framework; JS is tab
   switching + explorer filtering only (node-checked in tests). The Fiddler IA is
   cloned as information architecture, not as a SaaS.
2. **Conformance chip per run** comes from the same `expected_plan` path as the replay
   overlay, one definition of "required gates present" everywhere.
3. **30-day window** matches Fiddler's KPI windows; `--window-days` overrides.
4. **Runs without a START line surface with unknown lane** and no conformance chip:
   an untracked run is itself a signal (same stance as lane-telemetry).
5. **Build-time cost**: full build over 206 ledgers + 25 transcripts ≈ 0.5s, cheap
   enough to regenerate on demand; no cache, no second store (SPEC-182 stance).

## Test plan (executed in tests/test_dashboard.py)

- collect: 3 fixture ledgers -> run count, misfire count, override count, 30-bucket
  trends, event ordering.
- alerts: threshold crossing fires, non-crossing does not, empty-window rule.
- privacy: planted content string in a fixture transcript never reaches output.
- render: end-to-end fixture build; probes for every surface; JS `node --check`.

## Roadmap hooks

- Transcript-to-rid join (ID-420/423) upgrades Tool activity into the true
  MCP-and-PR view (session -> tools -> PR touched) and adds cost per run/PR.
- Verdict stream gains secret-guard events once a joiner exists (harness-plane
  enforcement made visible).
- `watch` mode (rebuild-on-change or SSE) turns the page from post-mortem into a
  live control plane; deliberately out of scope for the static prototype.

## v2 (same day): forge skin + the chart layer

Operator: "still far from full features with charts... this belongs to the forge
project... follow the design guide." Changes:

1. **Design system**: the render now implements `forge/docs/design/forge-design-
   guidelines.md` verbatim: coal/sheet/card grounds, ember accent, mono-led display,
   square corners, 1px-gap hairline grids, the 6px heat-spine ONCE per page, focus
   outlines, reduced-motion-safe. The generic indigo skin is retired.
2. **Charts (dataviz method)**: two single-hue area time-series with axes + native
   per-day tooltips (runs/day, gate records/day; one axis each, never dual); verdict
   mix per gate as stacked status bars (ok green / skip ash / override amber) with
   2px segment gaps and glyph secondary-encoding so identity is never color alone;
   single-hue breakdown bars (runs by repo, worker minutes by lane, top tools);
   day x hour activity heat grid as a sequential ember alpha ramp (the 4-stop heat
   ramp stays reserved for the spine per the guide).
3. **Palette validation**: `validate_palette.js` run on the status trio, both
   surfaces. Verdict: green/amber CVD delta sits in the 6-8 band, legal ONLY with
   secondary encoding, which every surface carries (glyphs + gaps + labels); the
   skip-gray chroma FAIL is intentional, skip is a non-event and the check scopes
   to categorical identity hues. Recorded here as the conscious exception.
4. **Ownership (forge boundary)**: generator + collectors stay in dwarves-kit
   (product code); the rendered page ships to `forge/site/dashboard/observability/`
   (forge owns the website), cross-linked with the Crew dashboard sidebar; the
   provenance banner carries the reproduce command.


## v3 (2026-07-25): agent-first, provider registries, sharing

1. **Frontend/data-plane split.** The TUI moved to the forge repo
   (`forge/cli/forge-tui`, product); the kit keeps `lib/bench/events.py` as the
   runtime-neutral data plane (protocol + adapters + conformance overlay). Every
   frontend consumes it, so a new runtime is one adapter, not a new UI.
2. **Agents are the primary user.** `dashboard.py stats` and `debt` emit JSON;
   `skills/observe` makes the surfaces auto-firable; the forge TUI mirrors the
   agent-facing verbs (`runs`/`debt`/`stats`, all `--format json`) with a parity
   matrix in `forge/cli/README.md` recording what is deliberately not duplicated
   (spend stays kit-side so one price table exists).
3. **Tool policy as capability → provider registries.** A capability (browser
   drive, computer use) lists interchangeable providers (harness / agent-browser
   / lightpanda / playwright / browserbase; macOS ladder / computer-use MCP /
   peekaboo / e2b), each with allow|ask|deny, a preferred-provider selector, and
   in-page custom rules. `hooks/tool-policy-guard.sh` normalizes v2 and legacy
   v1, so an old policy file keeps working.
4. **Config keys are editable** and export a per-project `.kit.toml` containing
   only changed keys (the inheritance model stays intact).
5. **Runtimes panel** answers "where do other LLMs render": the protocol is
   runtime-neutral, so each runtime needs one adapter. Detection is live
   (claude-code adapted; codex/pi/opencode/gemini/cursor detected with store
   stats and labeled detect-only).
6. **Sharing (pi.dev-shaped).** `#run/<rid>` deep-links open the explorer with
   that run's log expanded; every row has a Share button that copies the
   permalink and updates the URL. The unit of sharing is a run, not a page.
7. **Charts added:** full-conformance runs per day, runs-by-lane weekly stacked
   bars (fixed categorical order, legend always present), alongside the existing
   spend/runs/token/heat views.
8. **Efficiency ranking** per METRICS.md §8, with the volume floor and the
   absent-by-design cost-per-ship metric.
