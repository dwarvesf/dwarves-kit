# Decision Brief: the bench plane (comparative benchmarking over the existing ledgers)

Date: 2026-07-25 · Source: operator direction ("build the harness that has the numbers to back
the efficiency; benchmark different models, toolings, parts of the system", ops-toolkit session).
Status: DRAFT (design agreed in-session; feeds a spec). Consuming rows: ID-420, ID-421, ID-422.
Records: this brief; prior state in lib/stats/README.md + lib/telemetry/ + PHILOSOPHY §6 N6.

## Verified current state

The kit has a write plane (gate-ledger, lane-telemetry, proof-ledger, append-only) and a read
plane (lib/stats: stateless in-memory DuckDB lens, terminal + Artifact render, anomalies +
propose). Both are STATE views: they say what happened. Nothing can say "vs what": no run is
stamped with its configuration, no controlled replay exists, no baseline is comparable across
model / tool / module. Efficiency is a counterfactual claim; the counterfactual plane is missing.
N6's own gap list agrees: review-economics unmeasured (ID-392), one precision data point.

## The design

One harness, three dimensions. A frozen versioned SUITE is replayed under a CONFIG MATRIX
(model x active-modules x tool), each cell runs isolated and concurrent, is scored by the
existing verifiers, and lands as an immutable ledger row `suite-hash x config x outcome`.
Comparison, model profiling, and tool evals are then three GROUP BYs over one fact table,
rendered by the existing stats path. No new storage, no daemon.

### 1. Config stamping (prerequisite, do first)

Every ledger run row gains dimensions: model-per-stage, effort, kit version, active modules,
lane, task type, suite-hash (null for real work), session id. Token/cost joins in from
transcript parsing (the cc-observe parse) by session id. Every day without stamps is comparison
data lost forever; this is a small write-plane diff.

### 2. Concurrent matrix runner + live scoreboard (the fast-test ask)

`bench run --suite <s> --matrix <configs>` fans each (task, config) cell into an isolated
worktree via the existing wavefront/overnight-queue machinery; acceptance-verifier judges;
rows append to the ledger as they land. Presentation is a LIVE Artifact scoreboard (the stats
render path already does Artifact) that fills in as cells finish: watch five models x three
workflows race in one page. Nothing new is invented: worktree isolation, queue launcher,
verifier, render all exist; bench is the thin conductor.

### 3. Signal registry (the feedback-to-metric map)

`docs/verification/signal-registry.md`: one row per module/stage -> its KPIs -> its replay
command -> its current baseline row. When a user says "this part doesn't work", the registry
answers what metric to pull, what slice to replay, and what number it beat last time. Feedback
becomes a typed board row (defect-report) routed to a replay slice, queue-and-route with
receipts. A complaint with NO registry row is itself the finding: a coverage gap, filed as a
new probe. This is how the harness absorbs user feedback instead of debating it.

### 4. New-model protocol (the "model X just dropped" ask)

Baselines are immutable dated ledger rows keyed by suite-hash; a comparison is only valid on
the same hash. When a model drops: `bench profile <model>` runs the SMOKE tier (3-5 tasks per
task type, minutes, cheap) with only the model dimension changed; full tier only where smoke
shows promise. Output is a per-part capability profile ("beats the incumbent on worker stages,
loses on review lenses"), diffed against the stored baseline. The profile FEEDS the routing
table (SPEC-107 per-stage model defaults): routing stops being vibes and becomes the
benchmark's standing output. Re-running is cheap by construction (tiering), so "run it again
to be sure" is the default, not a project.

### 5. Tool suites as capability probes (the browser-use ask)

Tool evals fix the task and vary the tool. A tool suite is a set of CAPABILITY PROBES: for
browser-use, navigate, auth wall, form fill, lazy-load scroll, file download, anti-bot page.
Each probe = target + verifiable assertion + recorded artifact. Two target classes: PINNED
FIXTURES (self-hosted pages for mechanics; replay is deterministic forever) and a small LIVE
set for realism, drift-checked eval-refresh style before each replay so a broken probe is
distinguished from a broken tool. Every run records a watchable artifact (trace/screencast,
the proof-capture shape): that recording IS the user-facing proof that backs the claim.
Flake rate is a first-class metric (each probe runs 3x); a browser tool that passes 100% once
and 60% on repeat is the worse tool, and only replay reveals it. Same ledger schema, tool as
the config dimension, same scoreboard.

## North-star conformance (§6)

- **N6, primary**: every run emits measurable signals; profiles and anomalies feed the Learn
  staging file; the harness itself is measured (probe drift rate, suite coverage of feedback).
- **N5**: matrix runs are hands-off middle, bounded, telemetry'd, with a termination contract.
- **N4**: bench is a standalone module (a runner + plain JSONL/ledger rows + registry doc);
  delete the kit and `bench run` still scores a suite with the verifier script.
- **Meta-principles**: evidence before claims (the whole point); plain files (ledger rows,
  markdown registry); propose never dispose (profiles propose routing changes, human promotes).
- **Rejects**: a persistent metrics DB (SPEC-182 stateless stays), a dashboard daemon, any
  auto-tuning that rewrites routing without staging, a benchmark suite that only runs inside
  the plugin.

## Build sequence

1. Config stamping on the write plane (small diff, unblocks everything, retroactively priceless).
2. Signal registry v1 (a markdown table; no code; immediately makes feedback actionable).
3. `bench` module: suite freeze + matrix runner + profile/diff verbs + live scoreboard render.
4. First tool suite: browser-use probes (fixtures + live set), dogfooding the probe shape.

## 6. Testing the long workflow itself (added 2026-07-25, operator question)

A full kit lane is long, expensive, stochastic, and stateful; benchmarked as one black box
it yields too few runs to learn anything. Decision: cut it at stage seams and test each
question at the cheapest layer that can answer it, threaded by a workflow trace.

- **L1 scripted-model replay (free, every kit commit).** The engine (commands, hooks,
  gates, ledgers, board transitions) is deterministic; only the model is stochastic. A
  `scripted` executor replays canned stage outputs (recorded good runs + handcrafted fault
  injections) so a whole lane runs end-to-end in seconds. Asserts mechanism correctness:
  gate blocks, retry caps, verifier-fail -> fix-agent, board transitions; each mid-graph
  failure POLICY gets a fault-injection test (pins N5's unnamed failure semantics).
  Extends the kit's existing tests/, whole-lane replay rather than per-script units.
- **L2 stage benchmarks on golden inputs (cents, per stage change / model drop).** The
  workflow is a chain of artifact->artifact functions (brief->spec, spec->test plan,
  spec->diff, diff->verdict); freeze real past artifacts as per-stage suites and bench
  each stage per model. Highest info per dollar: the verifier stage with PLANTED defects,
  catch rate vs false-alarm rate on the clean twin = review-economics (ID-392). This
  layer, not E2E, is where per-part model capability profiles come from.
- **L3 few real E2E scenarios (dollars, nightly/release/new-model).** 3-5 fixture
  scenarios: brief -> shipped PR in a purpose-built sandbox repo with a real test suite
  ("shipped" is objective). Dims: routing profile, modules on/off (the kit-on vs kit-off
  headline lives here). Seeded variants test the workflow FRONT: an ambiguous brief
  (grill), a planted landmine (research-pitfalls). 3x repeats; composition only, because
  L1/L2 de-risk everything else.
- **The trace spine.** One run_id threads every stage into span rows (stage, agent,
  model, tokens, duration, verdict, artifact). Gate ledger + lane telemetry already hold
  pieces; threading them makes an E2E run a queryable tree: per-stage waterfall render,
  stage-resolved blame, and the feedback->metric loop lands on the L2 suite to extend.
  `layer` becomes one more dimension on the same fact table.

Consuming row: ID-423.

## Placement note

The harness and suites are product (this board). The published numbers, once real, are GTM
material and route to dfoundation (DF-153 family), cross-pointed per the placement rule.
