# Control-plane dashboard: design

> **Rev N = internal design revisions of this document, not releases.** The kit
> releases on plugin.json semver (currently 2.x) per forge `docs/design/kit-versioning.md`;
> nothing here implies a shipped version.

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

## Rev 2 (same day): forge skin + the chart layer

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


## Rev 3 (2026-07-25): agent-first, provider registries, sharing

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


## Rev 4 (2026-07-25): transcripts on the control plane

**The counts-only rule is now scoped, not absolute, and this is the record of that
change.** The original rule said transcript content is never read into any output. The
operator's control-plane requirement ("people should see clearly thru... from that they
can extract lessons or make commentary") needs the opposite for one surface. The rule
becomes:

- **Aggregates (default, everywhere):** the dashboard's Tool activity and Cost sections
  still read counts only, never content. Unchanged.
- **Transcript pages (opt-in, per invocation):** `dashboard.py transcript <session>`
  renders full content: prompts, assistant text, tool inputs and results. It is never
  produced by `build`, so no content appears unless someone asks for it by name.
- **Every rendered string passes a redaction mask** (`redact()`): provider keys, GitHub
  and Slack tokens, AWS access keys, bearer tokens, key=value secret shapes, PEM blocks.
  The page states the hit count and, crucially, states that a mask over free-form text
  **fails open** and is a safety net, not a guarantee.
- **Thinking content is never rendered** (only its size), tool payloads truncate at
  `--max-chars`, and the pages carry `noindex`.
- **Real transcripts are never committed to the site tree.** The site ships a synthetic
  fixture (`examples/fixtures/make_demo_session.py`) that plants a fake credential so the
  redaction is demonstrable; real ones render locally on demand. The forge site goes
  public at the P2 gate, so committed client work would be a leak with a timer on it.

Commentary and lesson extraction live on the page: per-turn notes persist in
localStorage (nothing is uploaded), "lesson" copies a markdown block with a deep link
back to the turn, and "Export notes" downloads them for the learning ledger.

**Efficiency board promoted** out of the Cost section into its own sidebar surface
(podium, grade distribution, weighting explainer, leaderboard, metric legend), because a
ranking buried in a spend table is not a board.


## Rev 5 (2026-07-25): the closing shape

Where this landed after the day's arc, recorded so the next session starts from reality
rather than from the commit log.

**Three planes, one protocol.**

| Plane | Owns | Lives in |
|---|---|---|
| Data | the event protocol, ledger + transcript adapters, the conformance overlay | kit `lib/bench/events.py` |
| Compute | fleet / money / debt / efficiency / allocation metrics, page renderers | kit `lib/bench/dashboard.py` |
| Frontends | the TUI (product) and the rendered site pages | forge `cli/forge-tui`, `site/dashboard/` |

Adding an agent runtime is one adapter in the data plane; nothing downstream changes.
Adding a metric is one function plus a section; the CLI gets it for free through `stats`.

**Surface inventory (8 verbs).** `stats`, `debt`, `allocation` (agent/JSON-first);
`build`, `session`, `sessions`, `transcript`, `transcripts` (rendered pages). The forge
TUI mirrors the three query verbs; spend and allocation stay kit-side deliberately so one
price table exists.

**The honesty rules, collected.** Each exists because a specific wrong number or leak was
possible, and each is enforced in code with a test:

1. Money is computed from list prices, never invoiced , said on every money surface.
2. Run-rate is `n/a` under two distinct days rather than extrapolating one partial day.
3. Period-over-period is suppressed when either bucket is partial.
4. Allocation proposals are bounded by demonstrated demand, and the remainder is reported
   as unallocated headroom rather than force-fed.
5. Cost-per-shipped-run is absent, not approximated, until the session↔run join lands.
6. Efficiency is token economics, not value delivered, and carries a volume floor.
7. Transcript content is opt-in, redacted best-effort, and the mask is described as
   fail-open; real transcripts never enter a publicly-shipping tree.
8. Feature attribution names `main`/`HEAD` as unattributed rather than inventing features.

**Known gaps, in priority order.** (a) The session↔run join (ID-420) unlocks cost per
shipped change, the metric that should dominate the efficiency board. (b) Per-member
identity needs the team gateway; everything member-shaped is project-shaped until then.
(c) Codex is the natural second runtime adapter , its rollout files are already JSONL.
(d) `watch` mode would make the dashboard live rather than a post-mortem.

## Rev 5.1 (2026-07-25): one dashboard, one sidebar

Han: "we should merge the Crew dashboard altogether, shouldn't have them separate."
The generated page's sidebar now carries an **Org** group (links to the forge Crew
views at `/dashboard/#<view>`, which is hash-routed on the forge side) and the Observe
group gained links to the generated session pages and transcripts. The forge Crew SPA
mirrors this with a **Fleet** group. The two render sources stay split, hand-authored
org views vs generated fleet pages, because they read different data (gateway-shaped
org state vs ledgers/transcripts); the merge is purely a nav contract. The `/dashboard/`
URL prefix is the one piece of forge coupling in this file; it predates this change
(the old "Crew dashboard" link) and is accepted as the cost of the generator being the
forge renderer. Full IA: forge `docs/design/crew-dashboard-recommendation.md` addendum.

## Rev 6 (2026-07-25): one page, and the kit becomes the backend

Han: "don't maintain 2 pages, merge/make them into one page... fully functioning
with design document, backend, frontend, deployment. think about the onboarding
phases and where a new team starts with no data."

### The split that ends the two-page era

The standalone generated page (`build`) is retired. The kit no longer emits ANY
page; it emits DATA. The forge SPA is the only page.

| Layer | Owner | Artifact |
|---|---|---|
| Frontend | forge `site/dashboard/index.html` | one SPA: 7 org views + 12 fleet views + 2 artifact links, one hash router, one sidebar |
| Data plane | kit `dashboard.py export` | `sections.json` (schema 1): 12 HTML fragments + `FLEET_JS` behavior + counts |
| Backend | forge-api worker | `GET/PUT /admin/observe`, one KV doc, Bearer-auth both ways |
| Deployment | static + push | commit `data/sections.json` for the static/demo path; `export --push <api>` for connected mode; `bundle.py` inlines the payload for single-file shares |

### The data contract (schema 1)

`{schema, generated_at, window_days, counts{runs,events,sessions,bench_cells,
alerts_firing}, sections{fleet,explorer,stream,tools,cost,efficiency,allocation,
runtime,debt,config,bench,alerts}, js}`. The section-id set IS the frontend
contract; `test_dashboard.py` asserts it, and the SPA's view shells mirror it.
Fragments carry kit class vocabulary; the SPA scopes the kit component styles
under `.fv` so the two stylesheets cannot fight. The behavior JS exposes exactly
three globals (`forgeFleetInit`, `forgeOpenRun`, and it consumes `forgeShow`),
which is the whole runtime interface between the planes.

### Onboarding: the honesty thresholds ARE the phase gates

A new team's day-0 dashboard is not blank, it is instructive. Every fleet view
renders a designed empty state (what the view shows, the exact feeder command,
and when it lights up). The Overview carries a getting-started strip whose phase
is computed, not configured:

| Phase | Trigger | What the user sees |
|---|---|---|
| 0 · no data | no payload loads | all fleet views show feed-it states; strip lists the first two steps |
| 1 · thin data | payload with < 25 runs or < 5 sessions | views render, but run-rate reads n/a (< 2 distinct days), period comparison stays suppressed (partial buckets), efficiency rows wait for the volume floor; the strip SAYS these are deliberate |
| 2 · steady | past the thresholds | strip removes itself |

No new thresholds were invented for onboarding: phase 1's "some numbers are n/a
on purpose" is literally the Rev 5 honesty rules doing their job on a small sample.

### Deployment note

The worker rejects non-export payloads (422), caps at 5MB (413), and both verbs
require the admin bearer because the payload embeds run ids, repo names and
project paths. Cloudflare's bot filter 403s Python-urllib's default UA; export
sends `dwarves-kit-observe/1` (found live, not in review).

## Rev 6.1 (2026-07-25): rich transcripts, the lane stepper, inferred stages

Three renderer upgrades, all server-side stdlib (escape-first, injection-probed in
tests): (1) transcript pages render assistant prose as markdown with fenced-code
syntax highlighting, Edit calls as red/green diffs, Write as highlighted file
content, Bash as a terminal line; user prompts stay literal on purpose (prompts
often contain markup-shaped text that must not render). (2) Kit session pages get
a lane-plan STEPPER: the expected workflow decorated with the record (● ○ ⚑ ◌ ·).
(3) Foreign-agent sessions (no gate ledger) get an INFERRED workflow strip,
classified per turn from tool usage (explore/build/verify/ship/talk), labeled as
a heuristic; the honest framing is the adoption pitch: kit runs replace the guess
with real gate records. Flow analysis: forge docs/design/dashboard-flows.md.
