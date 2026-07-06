---
title: "Scaling the Harness (arXiv 2605.26112): recap + audit of our agent stack"
date: 2026-07-04
purpose: >
  Deep-dive recap of Shangding Gu's "From Model Scaling to System Scaling: Scaling
  the Harness in Agentic AI" (arXiv 2605.26112), then a component-by-component audit
  of our own harness (CLAUDE.md rules, memory routing, dwarves-kit, mega-goal
  orchestration, ledger-observatory) against its six-component framework and three
  canonical failure modes. Ends with the telemetry closed-loop design for the paper's
  section 5 evaluation agenda. Design source for backlog rows ID-251..255.
source_repos: [ops-toolkit, dwarves-kit, dotfiles]
refresh_cadence: none
next_review: null
status: active
---

# Scaling the Harness: recap + audit (2026-07-04)

**Source:** https://arxiv.org/abs/2605.26112 (Shangding Gu, UC Berkeley; fetched via
arXiv HTML 2026-07-04). The paper benchmarks Claude Code and OpenClaw against its own
Python reference harness (CheetahClaws); we run two of the three.

## 1. The framework in one figure

Thesis: once the model is good enough, long-horizon performance is bounded by the
HARNESS, the structured system layer around the model. Performance over a horizon is
`P_H = f(R, M, C, S, O, G)`; model scaling improves only R, system scaling improves
the other five.

<svg viewBox="0 0 760 430" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Six-component harness loop mapped to our stack">
  <rect x="0" y="0" width="760" height="430" fill="#fafafa"/>
  <!-- O outer loop -->
  <rect x="14" y="34" width="732" height="330" rx="10" fill="none" stroke="#374151" stroke-width="1.6" stroke-dasharray="6 4"/>
  <text x="28" y="56" font-family="system-ui, -apple-system, sans-serif" font-size="13" font-weight="600" fill="#111827">O · orchestration loop</text>
  <text x="28" y="72" font-family="system-ui, -apple-system, sans-serif" font-size="10" fill="#6b7280">ours: /goal bounded loop · orchestrate.sh waves + Touches disjointness · worktree-per-writer · mega-merge · RUN_REPORT</text>
  <!-- M -->
  <rect x="40" y="100" width="150" height="64" rx="8" fill="#ffffff" stroke="#374151" stroke-width="1.4"/>
  <text x="115" y="126" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="13" font-weight="600" fill="#111827">M · memory</text>
  <text x="115" y="144" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="10" fill="#6b7280">durable knowledge</text>
  <text x="115" y="180" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">3-tier routing · learning-ledger</text>
  <text x="115" y="193" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">research/ frontmatter · GLOSSARYs</text>
  <!-- C -->
  <rect x="230" y="100" width="150" height="64" rx="8" fill="#ffffff" stroke="#374151" stroke-width="1.4"/>
  <text x="305" y="126" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="13" font-weight="600" fill="#111827">C · context</text>
  <text x="305" y="144" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="10" fill="#6b7280">per-turn assembly</text>
  <text x="305" y="180" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">CLAUDE.md priors · pointer budget</text>
  <text x="305" y="193" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">HOT/WARM handoff · cache hygiene</text>
  <!-- R -->
  <rect x="420" y="100" width="150" height="64" rx="8" fill="#eef2f7" stroke="#3b6ea5" stroke-width="1.6"/>
  <text x="495" y="126" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="13" font-weight="600" fill="#111827">R · reasoning</text>
  <text x="495" y="144" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="10" fill="#6b7280">the foundation model</text>
  <text x="495" y="180" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">Fable 5 daily · Model:/Effort: routing</text>
  <text x="495" y="193" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">sonnet default · opus for planning</text>
  <!-- S -->
  <rect x="596" y="100" width="130" height="64" rx="8" fill="#ffffff" stroke="#374151" stroke-width="1.4"/>
  <text x="661" y="126" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="13" font-weight="600" fill="#111827">S · skills</text>
  <text x="661" y="144" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="10" fill="#6b7280">tool/subagent router</text>
  <text x="661" y="180" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">auto-fire skills · tool ladders</text>
  <text x="661" y="193" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">30+ kit subagents</text>
  <!-- flow arrows -->
  <defs>
    <marker id="arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M 0 0 L 10 5 L 0 10 z" fill="#374151"/>
    </marker>
  </defs>
  <line x1="190" y1="132" x2="228" y2="132" stroke="#374151" stroke-width="1.4" marker-end="url(#arr)"/>
  <line x1="380" y1="132" x2="418" y2="132" stroke="#374151" stroke-width="1.4" marker-end="url(#arr)"/>
  <line x1="570" y1="132" x2="594" y2="132" stroke="#374151" stroke-width="1.4" marker-end="url(#arr)"/>
  <!-- S down to G -->
  <path d="M 661 164 L 661 232 L 540 232" stroke="#374151" stroke-width="1.4" fill="none" marker-end="url(#arr)"/>
  <!-- G -->
  <rect x="250" y="210" width="288" height="118" rx="8" fill="#ffffff" stroke="#3b6ea5" stroke-width="1.8"/>
  <text x="394" y="234" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="13" font-weight="600" fill="#111827">G · verification + governance</text>
  <text x="394" y="252" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="10" fill="#6b7280">gates actions AND memory write-backs</text>
  <text x="394" y="274" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">gate-ledger + ship-gate · proof-of-done with negative controls</text>
  <text x="394" y="288" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">secret-guard audit · quiz-gate + debt ledger (governs the HUMAN too)</text>
  <text x="394" y="302" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">ledger-observatory = the measurement of G itself</text>
  <!-- G back to M -->
  <path d="M 250 262 L 115 262 L 115 166" stroke="#3b6ea5" stroke-width="1.4" fill="none" marker-end="url(#arr)"/>
  <text x="130" y="256" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#3b6ea5">verified write-back only</text>
  <!-- caption -->
  <text x="380" y="404" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="10" fill="#6b7280">P_H = f(R, M, C, S, O, G) · model scaling improves R · system scaling improves the rest · grey text = our implementation</text>
</svg>

Temporal layers (paper section 3.2): **prompt** controls now (brittle over horizons),
**skill** controls this-class-of-things (fails by wrong routing/composition),
**memory** controls what survives (fails by drift, over-generalization, pollution).

## 2. The three bottlenecks and their named failure modes

| Component | Sub-axes | Canonical failure | System move |
|---|---|---|---|
| C context governance | relevance, compactness, traceability, refresh | **exposure without access**: the model sees more tokens but attends to the wrong ones; long context is not good context | context assembly as a selection policy; persistent priors + just-in-time refresh |
| M memory trust | precision, durability, retrievability, verifiability | **stale-but-confident**: a note true at write time whose target drifted; retrieval still ranks it; acting on it is destructive | trust re-established AT RETRIEVAL: staleness penalty, recall treated as hypothesis, re-verify against the live environment |
| S skill routing | specificity, selectivity, composability, verifiability | **confident-but-unchecked**: a specialized subagent returns plausible output nothing validates (the symmetric twin of stale-but-confident) | adaptive routing + post-condition checks as first-class parts of every skill spec |

Section 5 agenda: report **process metrics** with outcomes (tokens, tool calls,
retries, failed edits, human interventions, auditability); evaluate
**longitudinally** (memory hygiene, retrieval precision, minimal-context efficiency,
communication fidelity, long-session drift, verification-aware recovery, safety
under tool access); adopt an **evolution standard** (what persists / what updates /
what is measured / what is auditable). Anthropic's own multi-agent data point: token
usage alone explained 80% of performance variance.

## 3. Audit: our stack against the six components

| | Our machinery | Verdict |
|---|---|---|
| R | Fable 5 daily driver; per-sub-goal `Model:`/`Effort:` routing (sonnet default, opus planning, haiku trivial); non-caching router models banned from long sessions | GOOD. Routing is static-at-decompose, not adaptive; acceptable |
| M write side | 3-tier persistence (global chezmoi / repo git-tracked / machine scratch) = the paper's "what persists" separation; learning-ledger dedup gate (staging never storage); research/ frontmatter carries `refresh_cadence` + `next_review` + `superseded` | GOOD, ahead of most: an explicit staleness POLICY is rare |
| M retrieval side | "verify before recommending" exists as an instruction only | **WEAKEST AXIS.** Stale-but-confident is our live failure mode (see incident table) |
| C | cache-read hygiene rules (measured 58% of spend), ~4000-char pointer budget, HOT/WARM handoff tiers, thin+GUIDE skills, description-only skill loading | GOOD POLICY, WEAK ENFORCEMENT: 50h sessions still happen; nothing nudges. Global CLAUDE.md is a huge always-loaded prior (conscious tradeoff, still an exposure-without-access risk) |
| S | tool-selection ladders, auto-fire skills, 30+ specialized kit subagents with minimal toolsets, ToolSearch deferred loading | GOOD ROUTING, PARTIAL VERIFICATION: kit lanes measure misroute; the general skill layer has no misfire measurement and no uniform post-condition contract |
| O | waves + Touches disjointness, worktree-per-writer, kill-resilient checkpoints, conductor-assigned spec numbers, mega-merge refuse-on-failing-gate, RUN_REPORT | STRONG, battle-hardened. Remaining hole: communication fidelity, handoffs/summaries are unvalidated prose |
| G | gate-ledger + push-blocking proof-of-done WITH negative controls, audited overrides, secret-guard audit trail, understanding-gate (quiz + debt ledger), SPEC-136 silent-wave logging, ledger-observatory | STRONGEST LAYER, ahead of the paper (it does not consider governing the human's understanding). Gap: verification COST unmeasured until ID-245 ships |

### Incidents that ground the verdicts (our failures, the paper's names for them)

| Incident (all real, recent) | Paper failure mode |
|---|---|
| Compaction summary claimed the portable OPERATE.md was "GONE"; the installed copy existed (2026-07-04) | stale-but-confident + communication infidelity |
| A memory exists whose job is patching another stale memory (Capacities note) | memory drift, detected by hand not system |
| `caught=` emit shipped with no reader; `record` verb unwired for months | write-only ledger = verification without audit-read |
| grill 82% skip while being the highest-leverage pre-step | routing selectivity failure (unconditioned gate) |
| Hand-seeded test masked the debt-ledger seam until TIER-4 | confident-but-unchecked |
| Parallel branches claimed the same SPEC number; squash silently dropped an edit | orchestration/communication fidelity |
| This session is 50+ hours old against our own /clear rule | long-session drift, unenforced |

## 4. Absorptions (new work, prioritized)

1. **Memory trust at retrieval** (ID-251). Monthly **memory-verify sweep** (weekend-batch
   paydown pattern, manual command first, no new daemon): walk the memory stores
   (repo `.claude/memory/`, auto-memory, MEMORY.md indexes), extract referenced
   paths/flags/commands, test them against the live environment, emit a paydown
   table (dead refs, notes stale >180d). Propose fixes, NEVER auto-delete. Plus a
   `memories` lens in ledger-observatory (store, slug, written, last_verified,
   dead_ref_count) + a hygiene anomaly. V1 proxies retrieval precision via dead-ref
   rate; true recall-precision instrumentation is deliberately skipped (heavy,
   privacy-sensitive).
2. **Handoff-lint** (ID-252). Communication fidelity enforced at WRITE time: a
   checklist gate for HANDOFF.md / RUN_REPORT / compaction handoffs (every
   existence-claim verified this session; every PR/commit/file ref resolves; next
   actions runnable as written). Lands in OPERATE.md + the handoff skill; the
   cc-harvest PreCompact hook reminds.
3. **Skill post-conditions** (ID-253). The authoring standard (ops-tool-shape, skill
   template, kit meta-agent) gains a required "Post-condition: how the caller
   verifies my output" field, generalizing the kit's proof contract to the whole
   skill layer. Kills confident-but-unchecked at the root.
4. **Session-age nudge** (ID-254). The UserPromptSubmit hook already prints elapsed
   time; add a threshold line (elapsed > ~6h or heavy compaction count): "consider
   /clear or a handoff split". Trivial, enforces the existing cache-hygiene rule.

## 5. Telemetry design for the paper's section 5 agenda (the closed loop)

The observatory already has the right loop shape; the design is to make every
telemetry plane flow through it, and to hold one hard rule learned twice this week.

<svg viewBox="0 0 760 320" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="Telemetry closed loop">
  <rect x="0" y="0" width="760" height="320" fill="#fafafa"/>
  <defs>
    <marker id="arr2" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M 0 0 L 10 5 L 0 10 z" fill="#374151"/>
    </marker>
  </defs>
  <!-- nodes -->
  <rect x="24" y="60" width="128" height="76" rx="8" fill="#ffffff" stroke="#374151" stroke-width="1.4"/>
  <text x="88" y="84" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="12.5" font-weight="600" fill="#111827">EMIT</text>
  <text x="88" y="100" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">5 planes: run · session</text>
  <text x="88" y="113" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">memory · handoff · safety</text>
  <rect x="176" y="60" width="128" height="76" rx="8" fill="#ffffff" stroke="#374151" stroke-width="1.4"/>
  <text x="240" y="84" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="12.5" font-weight="600" fill="#111827">LENS</text>
  <text x="240" y="100" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">ledger-observatory</text>
  <text x="240" y="113" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">disposable DuckDB</text>
  <rect x="328" y="60" width="128" height="76" rx="8" fill="#ffffff" stroke="#374151" stroke-width="1.4"/>
  <text x="392" y="84" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="12.5" font-weight="600" fill="#111827">DETECT</text>
  <text x="392" y="100" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">anomalies: ceremony</text>
  <text x="392" y="113" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">runaway · hygiene · advisor</text>
  <rect x="480" y="60" width="128" height="76" rx="8" fill="#ffffff" stroke="#374151" stroke-width="1.4"/>
  <text x="544" y="84" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="12.5" font-weight="600" fill="#111827">PROPOSE</text>
  <text x="544" y="100" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">cc-backlog staging</text>
  <text x="544" y="113" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">add-backlog = human gate</text>
  <rect x="620" y="60" width="120" height="76" rx="8" fill="#eef2f7" stroke="#3b6ea5" stroke-width="1.6"/>
  <text x="680" y="84" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="12.5" font-weight="600" fill="#111827">SHIP</text>
  <text x="680" y="100" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">kit lanes + gates</text>
  <text x="680" y="113" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="9.5" fill="#6b7280">proof-of-done</text>
  <!-- forward arrows -->
  <line x1="152" y1="98" x2="174" y2="98" stroke="#374151" stroke-width="1.4" marker-end="url(#arr2)"/>
  <line x1="304" y1="98" x2="326" y2="98" stroke="#374151" stroke-width="1.4" marker-end="url(#arr2)"/>
  <line x1="456" y1="98" x2="478" y2="98" stroke="#374151" stroke-width="1.4" marker-end="url(#arr2)"/>
  <line x1="608" y1="98" x2="618" y2="98" stroke="#374151" stroke-width="1.4" marker-end="url(#arr2)"/>
  <!-- return arrow -->
  <path d="M 680 136 L 680 210 L 88 210 L 88 138" stroke="#3b6ea5" stroke-width="1.6" fill="none" marker-end="url(#arr2)"/>
  <text x="384" y="203" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="10.5" fill="#3b6ea5">re-measure: shipped changes show up in the next digest</text>
  <!-- hard rule banner -->
  <rect x="24" y="240" width="716" height="52" rx="8" fill="#ffffff" stroke="#3b6ea5" stroke-width="1.4"/>
  <text x="382" y="262" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="11.5" font-weight="600" fill="#111827">HARD RULE (learned twice): an emitter may only land in the same PR family as its reader.</text>
  <text x="382" y="280" text-anchor="middle" font-family="system-ui, -apple-system, sans-serif" font-size="10" fill="#6b7280">caught= shipped with no reader; the record verb sat unwired for months. Write-only telemetry is the recurring disease.</text>
</svg>

### 5.1 The five telemetry planes

| Plane | Emitter (today) | Reader (today) | Gap / action |
|---|---|---|---|
| **Run** | `gate-ledger.sh` (63+ runs; `caught=`/START/END per kit #158; DEBT lines per SPEC-136; skip `reason=` pending ID-247) | `kit_runs` shipped; per-gate `kit_gates` queued | ID-245 (gate-yield, defect-correlation) + ID-248 (deviation-rate) |
| **Session** | Claude Code transcripts (`~/.claude/projects/*.jsonl`): tokens in/out/cache-read, tool calls, errors, compactions, canary lines | NONE | **ID-255**: numeric-only `sessions` adapter (counts, sizes, durations; NEVER content) |
| **Memory** | none at runtime (write side has learning-ledger) | none | ID-251 sweep-based (deliberately NOT runtime instrumentation) |
| **Handoff** | HANDOFF.md / RUN_REPORT / compaction summaries | humans | ID-252 lint at write time (fidelity enforced, not post-hoc measured, v1 ceiling stated honestly) |
| **Safety** | secret-guard audit log, hook blocks | status script only | fold bypass/block counts into ID-255's `safety` table |

### 5.2 Design principles (the ones our incidents actually taught)

1. **Read-side first.** An emitter lands in the same PR family as its reader, no
   exceptions (the banner above).
2. **Sweep over instrument.** Where a periodic re-verification answers the question
   (memory trust), do not add runtime hooks or daemons. Minimum infra.
3. **Numbers, not content.** The sessions adapter extracts counts/sizes/durations
   only; transcripts hold secrets and personal data, and the lens must stay safe to
   query casually.
4. **Propose, never auto-file.** Anomalies stage into cc-backlog; `add-backlog` is
   the human gate (shipped contract, keep it).
5. **One lens.** Every plane materializes into the same disposable DuckDB;
   cross-plane JOINs are the payoff (e.g. session tokens x run gates = cost per
   verified outcome).
6. **Counterfactual-in-same-row** (credit pxpipe). Every request/run logs billed usage
   AND a free counterfactual (e.g. `count_tokens`) in ONE record, so a savings claim
   carries no cross-run confound; credit a warm cache only when the request proved it.
7. **Honest-negative** (credit pxpipe). A mechanism that net-loses reports negative,
   never filtered out of a digest or scorecard.

### 5.3 North-star standing queries (the three metrics, made durable)

| Metric | Standing query (post ID-245/248/255) |
|---|---|
| Token efficiency | output + cache-read tokens per shipped PR / per sub-goal; session re-read ratio; cost per verified outcome (sessions x kit_gates JOIN) |
| Time-to-done | wall time per sub-goal; wave utilization (serial-when-parallel from the advisor); slow-gate ranking |
| Coverage | coverage-delta rows per substantial sub-goal; gate-yield caught-rates; deviation-rate classes |

### 5.4 Paper Table-4 dimensions, mapped

| Paper dimension | Our instrument |
|---|---|
| One-shot completion | shipped/review in `kit_runs` (live) |
| Memory retrieval precision | dead-ref rate proxy (ID-251); true instrumentation skipped |
| Memory hygiene | memory-verify sweep + hygiene anomaly (ID-251) |
| Minimal-context efficiency | sessions adapter token/re-read metrics (ID-255) |
| Communication fidelity | handoff-lint at write time (ID-252) |
| Long-session drift | session-age nudge (ID-254) + canary-drop count in sessions (ID-255; the 🐱 canary is ALREADY a per-turn drift detector, count it) |
| Verification-aware recovery | kill-resilience discipline in OPERATE; recovery events loggable later if they recur |
| Safety under tool access | secret-guard counts into the lens (ID-255) |

### 5.5 Cadence (how it keeps improving)

- **Weekly**: `ledger digest` (part of ID-255): render the north-star scorecard +
  `anomalies --propose`. One command, human reviews staged rows.
- **Monthly**: memory-verify sweep (ID-251), paydown table like weekend-batch.
- **Per mega-goal close**: RUN_REPORT (shipped) + gate-yield delta vs the prior run.
- **Evolution standard (paper 5.3), answered once:** what persists = the 3 memory
  tiers + skills + gates; what updates online = memory + backlog staging (everything
  else, CLAUDE.md / skills / hooks / gate definitions, is chezmoi- or PR-gated
  review); what is measured = the observatory planes above; what is auditable = rid
  ledger, proof ledger, secret-guard log, PR trail. We already satisfy the standard;
  this paragraph just makes it explicit.

## 6. Verdict

Strong on O and G (ahead of the paper: proof gates with negative controls, and
governance of the human's understanding, which the paper does not consider). Good on
M-write and C-policy. Weak exactly where the paper predicts pain: M-retrieval trust
(stale-but-confident, our live failure mode) and uniform S post-conditions. The
paper's section 5 agenda is not new work for us, it is a validation of the
ledger-observatory thread (ID-245/248); the genuinely new absorptions are
ID-251..255.
