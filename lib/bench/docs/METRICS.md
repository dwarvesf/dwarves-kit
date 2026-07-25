# The metric contract

What the bench plane measures, why each number exists, and where each number is
shown. This is the single reference for "what metric backs which claim". Every
published efficiency claim must trace to a metric here, and every metric here
names its source and its replay. A claim with no metric row is marketing;
a metric with no replay is a rumor.

Status column: `now` = the bench.py prototype emits it today; `join` = derivable
by joining existing kit ledgers/transcripts, wiring queued; `planned` = needs a
collector that does not exist yet (each carries a board row before build).

## 1. Outcome quality (does the work actually pass?)

| Metric | Definition | Source | Surface | Status |
|---|---|---|---|---|
| First-pass yield | % of tasks passing acceptance with zero human fixes and zero retries | bench row `pass` | user + internal | now |
| Pass-after-retry | yield after the bounded worker->verifier->fix loop (pass@k analogue) | run ledger retries | internal | join |
| Test granularity | tests passed / total per cell, not just the boolean | bench row | internal | now |
| Defect caught rate | defects stopped by a gate/verifier before ship (`caught=bool`) | gate-ledger | user + internal | join |
| Defect escape rate | defects found AFTER ship, per shipped task; the denominator of gate value | incident/feedback rows | user + internal | planned |
| Verifier disagreement | task-verifier PASS later overturned by acceptance/system verifier; measures verification quality itself | verifier records | internal | join |
| Spec fidelity | logged deviations per task (implementation-notes deltas) | impl-notes | internal | planned |

## 2. Efficiency (what does a shipped task cost?)

| Metric | Definition | Source | Surface | Status |
|---|---|---|---|---|
| Cost per shipped task | USD (API) or token-equivalent per task that reached shipped | bench `cost_usd`; transcripts by session id | user + internal | now (bench) / join (real work) |
| Wall-clock per task | end-to-end duration, and split queue-wait vs execution | bench `duration_s`; board timestamps | user + internal | now (bench) / join |
| Token profile | input/output/cache split; cache-hit ratio (cache-read is the dominant cost slice) | transcripts | internal | join |
| Rework ratio | fix-agent dispatches / tasks | run ledger | internal | join |
| Retry distribution | histogram of retries per task, not just the mean | run ledger | internal | join |
| Cost-quality frontier | yield vs cost scatter per config; the routing decision IS picking a point on this frontier | bench rows | user + internal | now (derivable from rows) |

## 3. Autonomy (is the middle actually hands-off? N5's claim)

| Metric | Definition | Source | Surface | Status |
|---|---|---|---|---|
| Intervention count | human touches per run between define-done and judge-artifact | session transcripts | user + internal | join |
| Unattended stretch | longest continuous hands-off span per run | transcripts | internal | join |
| Question-ending rate | % of runs ending on a question the loop could have answered itself | run ledger | internal | join |
| Termination honesty | % of runs claiming done whose recorded verification actually passed | proof-ledger vs claims | user + internal | join |

## 4. Reliability (is the number stable, or did we get lucky once?)

| Metric | Definition | Source | Surface | Status |
|---|---|---|---|---|
| Flake rate | variance of pass across `--repeats N` of the identical cell; a tool that passes once and fails on repeat is the worse tool | bench repeats | user + internal | now (`--repeats`) |
| Config variance | outcome delta when re-running the same config on the same suite hash | bench rows | internal | now (derivable) |
| Probe drift rate | live-target probes broken by the ENVIRONMENT (site changed), not the tool; separates "probe rotted" from "tool regressed" | tool-suite drift check | internal | planned (tool suites) |
| Harness error rate | cells that errored in bench itself rather than failing the task | bench `error` | internal | now |

## 5. Comparative (the counterfactual plane)

| Metric | Definition | Source | Surface | Status |
|---|---|---|---|---|
| Capability profile | per-model (or per-tool) yield broken down by task type / stage | bench rows grouped | user + internal | now (grouping exists; more task types needed) |
| Baseline delta | candidate vs stored baseline on the SAME suite hash: fixed / regressed / cost delta | `bench diff` | user + internal | now |
| Kit-on vs kit-off | the headline number: same suite, agent executor, gates on vs raw model | bench matrix (executor + modules dims) | user | planned (modules dim not yet togglable) |
| Module ablation | delta attributable to one module enabled vs disabled | bench matrix | internal | planned |

## 6. Trust and presentation (can a user believe the number?)

| Metric | Definition | Source | Surface | Status |
|---|---|---|---|---|
| Proof coverage | % of shipped tasks carrying a proof-of-done artifact | proof-ledger | user | join |
| Evidence freshness | age of the newest baseline backing each published claim; stale evidence demotes the claim | bench row `ts` | user | now (derivable) |
| Claim-to-proof link rate | % of published numbers that link a replayable run + watchable artifact | trust page audit | user | planned |
| Suite coverage of feedback | % of user complaints that map to an existing registry row / probe; unmapped complaints are coverage gaps | signal registry | internal | planned |

## 7. The meta-loop (N6: the harness measures itself)

| Metric | Definition | Source | Surface | Status |
|---|---|---|---|---|
| Learn-propose precision | % of auto-proposed rows a human promotes | staging + board | internal | join (exists, one data point) |
| Feedback-to-replay latency | time from "this part doesn't work" to a replayed slice with a verdict | registry + bench rows | internal | planned |
| Registry coverage | % of modules/stages with a mapped KPI + replay command | signal registry | internal | planned |

## Presentation: two surfaces, one data path

Both render from the same rows (the stats single-data-path rule); they differ
only in selection and framing. Never maintain a second dataset for marketing.

1. **Internal scoreboard** (operators): everything above; anomalies feed
   `learn propose`. Terminal table + Artifact via the stats render path;
   `bench render --html` is the standalone fallback.
2. **User trust page** (buyers/users): the six headline numbers only, each with
   three mandatory attachments: the replay command that reproduces it, the
   suite hash + date it was measured on (freshness stamp), and where available
   a watchable artifact (trace/screencast for tool probes). A number without
   its attachments does not go on the page.

## Provenance rules (what makes a number citable)

- **Immutable rows.** runs.jsonl is append-only; a correction is a new run,
  never an edit.
- **Same-hash comparisons only.** `bench diff` warns loudly across differing
  suite hashes; cross-hash deltas are narrative, not evidence.
- **Config completeness.** A row missing its config dims (model, executor,
  modules, kit version) cannot enter a comparison.
- **Hand-verified seeds.** Suite expected-values are worked by a human before
  any model runs the task (N3); a suite whose ground truth was model-generated
  is disqualified as evidence.
- **Checks are hidden from executors.** check.py enters the cell only after
  the run, so an agent can never read the verifier and overfit.
- **Privacy gate on publish.** The trust page passes the til-style strip:
  no client/NDA task content in suites, no account ids, no personal paths.


## 8. Token efficiency (who spends tokens well)

Ranking metrics computed from transcript usage, exposed as the Cost section's
efficiency table and via `dashboard.py stats`. "Member" is the project on a solo
host; real per-member identity arrives with the team gateway (the token pool).

| Metric | Definition | Rewards | Status |
|---|---|---|---|
| Unit cost of output | USD per million output tokens (lower better) | cheap routing + brevity: producing work per dollar | now |
| Cache discipline | cache-read ÷ total prompt tokens | stable prefixes, `/clear` hygiene, not re-reading the world each turn | now |
| Delegation leverage | share of output tokens from cheap models (haiku/sonnet) | cheap-first routing instead of premium-everything | now |
| Fresh-input frugality | fresh input tokens per session | not re-pasting what the cache already holds | planned |
| **Cost per shipped run** | spend ÷ conformant ships | the metric that actually matters: outcome efficiency, not token thrift | planned (needs the session↔rid join, ID-420) |

**Composite score.** Each metric is min-max normalized across members, then
weighted 40% unit cost / 30% cache discipline / 30% delegation leverage.
Grades: A ≥ 80, B ≥ 65, C ≥ 50, D ≥ 35, else E.

**Two honesty rules, both enforced in code.** A volume floor (default $1)
excludes members whose sample is too small to rank, so one tiny session cannot
top the board. And cost-per-shipped-run is *absent rather than approximated*:
without the session↔rid join there is no defensible denominator, and a made-up
one would rank people on fiction. When ID-420 lands, it becomes the headline
metric and the three current ones become its explanations.

**What the ranking is not.** It measures token economics, not value delivered.
A member doing the hardest work can rank mid-table by spending premium tokens
well. Read it as a routing-and-hygiene signal, never as a performance review.


## 9. Pool allocation (lead-facing)

The lead's question is not "how many tokens" but "where did my pool go, and what should
next period's allowances be". Three dimensions, one proposal.

| Dimension | Source | Honesty note |
|---|---|---|
| Member | project directory on a solo host; gateway identity when the team layer ships | stated on every surface |
| **Feature** | the **git branch** each session worked on, cost split across branches by message share | `main` / `HEAD` / no-branch are reported as **unattributed**, never dressed up as features |
| Period | ISO week or calendar month | partial buckets are flagged and period-over-period comparison is suppressed when either side is partial |

### The allowance proposal

`weight = spend x grade multiplier` (A 1.15 · B 1.05 · C 1.00 · D 0.90 · E 0.80), then
water-filled into the budget under three guards:

- **Demand ceiling** , no proposal above 1.5x what a member actually spent. Nobody absorbs
  a 12x jump in one period.
- **Concentration cap** , no proposal above 40% of the pool; a member whose *current* spend
  already exceeds it is flagged as needing a decision, not a slider.
- **Starvation floor** , a minimum allowance, itself capped at 3x demonstrated demand so
  the floor cannot inflate a small spender. A member with no history gets the plain floor
  so they can start.

Budget that fits nobody's ceiling is reported as **unallocated headroom**. Two bugs were
caught by running this on real data and are now regression-tested: force-feeding the
residual to tiny members (a $44 spender proposed $549 because a $3.9k member hit the cap),
and the floor lifting a $50 spender to $1,250.

**The plan is a proposal.** It is exported, never applied. Efficiency grades measure token
economics, not value delivered, so a trim is a conversation opener, not a verdict.

### Surfaces

- Web: **Pool allocation** section (share bars, member x feature matrix, period comparison,
  proposed plan with reasons).
- CLI: `dashboard.py allocation --period week|month [--budget N] [--format text|json|md]`.
  `--format md` is the weekly/monthly report a lead can paste into a channel.
