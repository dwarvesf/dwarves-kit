---
title: Claude Code Hooks + Tools, Elevation Map and Adoption Plan
date: 2026-06-14
purpose: >
  Reference for pushing my Claude Code setup past the guard/format/notify/inject
  quadrant it already saturates. Maps six frontier use-case axes, records the
  decisions on five open questions (prose-RAG fit, observability tooling,
  auto-harvest, citation verification, proactive sweeps), tears down the
  community setups worth borrowing, and holds the adoption roadmap (a living
  tracker). Use when deciding what hook/tool/skill capability to build next.
source_repos: [ops-toolkit, dotfiles]
refresh_cadence: as-needed
next_review: 2026-09-14
status: active
---

# Claude Code Hooks + Tools: Elevation Map and Adoption Plan

## Why this exists

My current setup already runs 12 hook events, 23+ hook scripts, 87 skills, a
hardened 33-rule deny list, and the dwarves-kit gate system. There is no unused
hook *event* left to light up. The remaining headroom is a different class of use
case: getting the agent to reason about *itself* and about *my accumulated
knowledge*, not just police the current edit. This note maps that headroom.

## Current position (what is already saturated)

Guards (pipe-to-shell, rm-rf, secret-guard x4 surfaces, commit-format, ship-gate,
branch-protection), formatting (auto-format, em-dash-fix), context injection
(repo-memory exact-match, machine-banner, codebase-index, context-readiness,
spec-intent), notifications (peon-ping across 7 events), session hygiene
(terminal-title, LAB_LOG closer, session-state-save), learning-capture prompt on
Stop, worktree isolation, 87 skills. All of this is the GUARD / FORMAT / NOTIFY /
INJECT quadrant. It is maxed.

## The six frontier axes

| Axis | What it unlocks | Today | Elevation delta |
|---|---|---|---|
| 1. Context retrieval | Inject the *right* knowledge per prompt, dynamically | repo-memory (exact-match index), spec-intent | Semantic RAG over vault + til + ledger |
| 2. Self-observability | Measure my own AI usage like a system I run | peon-ping signals; nothing measured | Tool/skill analytics + hook latency into vps-mon |
| 3. Closed-loop improvement | The setup improves the setup | manual `/learned`, narrate-*, extract-workflow | Auto-harvest at PreCompact; repeat-sequence detection |
| 4. Domain fusion | Wire sessions into Notion / Hermes / Discord | LAB_LOG; Hermes (separate) | Stop-hook routing of ops outcomes (privacy-gated) |
| 5. Correctness deepening | Verify *truth*, not just shape | show-without-run, spec-drift, proof-of-done | Citation / file:line verification; adversarial-verify |
| 6. Proactive agency | Agent acts unprompted on a schedule | launchd + Hermes daemons | Cron / Routines for cross-repo sweeps |

Highest leverage for me: 1, 2, 3. Detail and the five open-question decisions follow.

---

## Axis 1, Context retrieval (semantic RAG over my own knowledge)

**The asset:** an Obsidian vault with a live vector DB (`.smtcmp_vector_db`), plus
`til`, `research/`, `learned-ledger.md`, years of notes. `repo-memory` injects an
*exact* index file today; the elevation is *semantic* retrieval injected per prompt.

**Mechanism:** `UserPromptSubmit` hook -> embed the prompt locally on the Air
(fastembed, ONNX/CPU, e.g. `bge-small`) -> vector search a small prose index ->
inject top-k relevant prior notes as `additionalContext` ("You wrote about this before: ...").

### Q1 decision, do codebase-memory or Serena fit this?

**No. Both are code-structure tools, not prose-semantic tools.** Confirmed from
my own eval (`experiments/codebase-tool-benchmark/`,
`research/2026-06-06-serena-vs-codebase-memory-benchmark.md`):

- **codebase-memory-mcp**: AST graph (tree-sitter) + file map; indexes markdown as
  first-class graph *nodes* (79 md nodes in the test, headings/sections) but does
  **no embeddings and no semantic search**. Retrieval is structural (pointers to
  files/lines), not by-meaning.
- **Serena**: LSP symbol layer for code; **cannot even extract markdown symbols**
  ("Cannot extract symbols from file README.md"); markdown falls back to text
  pattern-search only.

My use case needs vector embeddings of prose + similarity search + cross-ledger
dedup. Neither tool provides any of the three. They solve "where is this symbol /
what calls it" (code navigation), a different problem.

**What fits instead:** build a tiny dedicated prose-RAG index.
- Embeddings: a small model on the Air via fastembed (ONNX/CPU, local, free, private).
  NOT the Mini (qwen TPS unreliable), NOT Claude (no embeddings API). Voyage AI is
  the cloud alternative if local quality is insufficient.
- Store: `sqlite-vec` or a flat vector file; corpus = `til` + `research/` +
  `learned-ledger.md` (+ optionally the vault).
- Query surface: a small CLI the `UserPromptSubmit` hook calls.
- Do *not* parasitize the `.smtcmp` Obsidian DB (plugin-internal format, brittle).
- "Claude Context" MCP (Zilliz/Milvus) exists for semantic *code* search; still
  code-oriented, so DIY prose index is cleaner.

**Gotchas:** relevance floor or it injects noise; cache to keep latency < ~100ms;
keep it local on the Air (no prose leaves the machine).

---

## Axis 2, Self-observability (treat my AI usage as a monitored system)

I run vps-mon and I am an ops person, yet my own Claude Code usage is the one
system I do not instrument.

### Q2 decision, market scan for skill analytics + hook latency

**No single off-the-shelf tool covers both skill-use analytics AND hook latency.**
Landscape:

| Tool | Measures | Skill analytics | Hook latency | Notes |
|---|---|---|---|---|
| `ccusage` (npm) | token / cost from JSONL | No | No | cost CLI only |
| ColeMurray/claude-code-otel | OTel -> Prometheus/Grafana | No | **Yes** (`claude_code.hook_execution_complete`) | full Docker stack |
| Native OTel (`CLAUDE_CODE_ENABLE_TELEMETRY=1`) | token/cost/session | No | not separately exposed | built in |
| Marketplace "Skill Usage Tracker" | skill invokes + time/cost | **Yes** | No | maintenance unknown |
| TechNickAI/claude_telemetry | tool calls, traces -> Datadog/Sentry | unclear | unclear | `claude` -> `claudia` wrapper |

**Recommendation (fits my infra, avoids a second monitoring stack):**
- *Hook latency*: my hooks are bash and I own them. Wrap each in a timer that
  appends `{hook, ms, event}` to a log vps-mon already tails. Trivial, no OTel
  stack. (Or scrape native OTel's hook event if I want it standardized.)
- *Skill analytics*: no clean off-the-shelf for my need. Parse the session JSONL
  (Skill tool calls appear there) into a weekly "which of 87 skills fired vs
  rotted / error rate" report. Small script on a launchd/Cron cadence -> vps-mon.
- Steal claude-code-otel's **metric schema**, not its Docker/Grafana stack.

Honest take: mostly DIY, but cheap DIY because vps-mon is already the sink.

---

## Axis 3, Closed-loop improvement (auto-harvest knowledge)

### Q3, current pipeline + what else to push

**Current state (mapped):** capture is **all manual / on-demand**. The only silent
automation is the `learned-ledger.md` row append when a teaching skill
(`concept-explain`, `deep-understand`, `knowledge-capture`) fires. Narrate-*,
handoff, flush are manual or end-of-session suggestions.

Pipeline today:
```
teaching skill / "save this"  ->  learning-ledger:capture (dedup + queue row)
                                      -> learned-ledger.md (status: queued)
at session close (manual)      ->  learning-ledger:flush -> GLOSSARY | til | research | drop
narrate-log / narrate-experiment (manual) -> narrative drafts -> (promote) til/hedgenotes/fromwu
```

**Gaps:** no mid-session sensing of a learning moment; **no PreCompact harvest**
(knowledge is lost at compaction); no cross-session synthesis (same concept across
3 sessions never auto-merges); no pre-PR capture hook.

**Auto-harvest design (the thing I want):**
- **Primary trigger = `PreCompact` hook.** This is the exact moment knowledge is
  about to be destroyed. Hook reads `transcript_path`, runs a cheap pass (Claude
  Haiku via API or `claude -p`; the transcript is already in an Anthropic session,
  so no new exposure) to extract durable decisions / gotchas / concepts as ledger
  rows, dedups against `learned-ledger.md` + GLOSSARYs, appends new rows as
  `status: queued`. Flush stays manual (human-in-loop keeps noise out of durable
  homes).
- **Secondary = `SessionEnd` hook**: same harvest on clean exit, not just compaction.
- **Upgrade the existing Stop-hook capture prompt**: instead of only nagging,
  cheap-classify whether the turn held a root-cause / decision and auto-stage a row.
- **Beyond narrate (what else to push):**
  - *Cross-session synthesis*: weekly job reads ledger + GLOSSARYs, proposes merges
    (the "agentkernel appeared 3x" case) -> `knowledge-capture:consolidation`.
  - *Repeat-sequence detection*: detect a manual sequence done 3x across sessions
    -> auto-suggest `extract-workflow` (automating its own trigger).
  - *Auto-promotion*: execute the learning-ledger Tier-2 nudge (topic hits ~5
    concepts -> propose a `learning/<topic>` track) from the same weekly job.
- **Constraints:** harvest uses a cheap Claude model (Haiku); the transcript is
  already with Anthropic so no new exposure; auto-*stage*, manual-*flush*.

---

## Axis 4, Domain fusion (brief)

A `Stop` hook could append ops-session outcomes to a Notion DB / Discord via MCP.
High value but **privacy-gated**: family-office / trading / NDA sessions must never
push. Only worth it scoped to an explicit ops-repo allowlist. Lower priority than 1-3.

---

## Axis 5, Correctness deepening (citation + adversarial verify)

### Q4, how to implement file:line verification + adversarial-verify

**Key fact the research clarified:** `Stop` / `SubagentStop` hooks **do** receive
`transcript_path` in their JSON input, so a Stop hook *can* read the final
assistant message. Two paths:

**Path A, deterministic Stop hook (cheap, catches the common case).**
- On Stop: read `transcript_path`, take the last assistant message.
- Regex out every `path:line` and bare `path` reference.
- For each: file exists? if a line is cited, file has >= that many lines?
  optionally grep the cited symbol near that line.
- Unresolved citation -> block (exit 2 / `decision: block`) listing the bad refs so
  I fix before it is trusted; or non-blocking warn to a log if friction is unwanted.
- Limitation: verifies *existence*, not semantic truth ("does line 42 do what was
  claimed"). For that, a model is required.

**Path B, adversarial-verify subagent (semantic, for high-stakes claims).**
- Dispatch a read-only verifier (I already have `task-verifier`,
  `integration-checker`, `kit:reviewer`) that re-reads cited files and checks the
  *claim*, not just existence.
- Or the Workflow "adversarial verify" primitive: spawn N skeptics prompted to
  REFUTE; kill the claim if a majority refute.
- Trigger on-demand (`/verify`, which I have) or via a Workflow, **not** every Stop
  (latency + cost).

**Recommendation:**
- Build **Path A** as a Stop hook for citation hygiene. Genuinely missing, and I
  treat my own output as source-of-truth, so hallucinated file:line refs are a real
  risk. Start non-blocking (log), promote to blocking once tuned.
- Keep **Path B** on-demand for semantic correctness of important claims. Do not
  auto-run per turn.
- Existing real implementations are thin: PostToolUse validators (disler) and
  subagent verifiers are shipped; Stop-hook fact-checking is mostly DIY. Path A is
  ours to build.

---

## Axis 6, Proactive agency (cross-repo sweeps)

### Q5, elaborated use cases

Mechanism: `Cron` tool / claude.ai Routines (scheduled cloud CC session, needs *my*
reasoning) OR a launchd + Hermes job (preferred for deterministic, persistent work,
per minimum-infra rule). Tailored to my ~25 repos:

| # | Sweep | Needs reasoning? | Route |
|---|---|---|---|
| 1 | **Backlog triage**: read each repo's BACKLOG/TODOs/FIXMEs, dedup, re-prioritize, flag stale rows, one digest to Discord/Notion (the work-intake "reconcile the board", automated) | Yes | Routine / Hermes-agent |
| 2 | **Learning-capture flush**: nightly flush of leftover `learned-ledger.md` queued rows + run the cross-session synthesis (Axis 3) | Yes | Routine / Hermes-agent |
| 3 | **Stale-branch / WIP sweep**: branches older than N days with unmerged work; abandoned `.claude/worktrees/` | No | script + digest |
| 4 | **Dependency / security sweep**: npm/pip/uv audit + patch-exploit advisory check across deployed repos; digest only actionable | Partly | script + agent triage |
| 5 | **Doc-drift sweep**: per repo, does CLAUDE.md / README match reality (kit:docs / doc-verifier pattern) | Yes | Routine / Hermes-agent |
| 6 | **Memory/ledger hygiene**: scan each `.claude/memory/MEMORY.md` for refs to files/flags that no longer exist (honors the "verify before recommending" rule) | No | script + digest |
| 7 | **Proof-of-done gaps**: scan `tools/` for any tool missing `docs/proof-of-done.md` | No | script + digest |
| 8 | **Topology reconcile**: drift between `tool.toml` files and `MANIFEST.md` / `CONSUMERS.md` (SPEC-044 hand-maintained today) | No | script + digest |

Backlog triage and learning-capture flush are the two you flagged; both need
reasoning, so Routine or a Hermes-agent job fits. The deterministic ones (3,6,7,8)
are scripts that just post a digest.

---

## Part 2, External setups, torn down

Ranked by what an expert actually extracts.

### 1. disler/claude-code-hooks-mastery, clone and read
Reference implementation: all 13 hook events wired, CI-validated.
- **Steal:** the **meta-agent** (an agent that generates subagents from a
  description); the **builder + validator team loop** (`/plan_w_team` = all-tools
  builder + read-only validator against acceptance criteria, my dwarves-kit pattern
  in miniature); the **TTS provider chain** (ElevenLabs -> OpenAI -> local pyttsx3,
  clean multi-provider fallback).
- **Also demonstrates:** PreCompact transcript backup (relevant to Axis 3).
- https://github.com/disler/claude-code-hooks-mastery

### 2. ColeMurray/claude-code-otel, steal the schema, not the stack
OTel instrumentation: `make up` -> OTel Collector + Prometheus + Loki + Grafana.
- Captures `claude_code.cost.usage` per model, token counts (incl. cache),
  tool success rates, permission decisions, **hook execution latency**
  (`claude_code.hook_execution_complete`), 30s error tail.
- **Steal:** the metric schema for Axis 2; wire the gRPC endpoint (4317) into
  vps-mon; drop the Docker stack.
- https://github.com/ColeMurray/claude-code-otel

### 3. rohitg00/awesome-claude-code-toolkit, one pattern
Ships `temporal-core`, `idle-timing`, `claude-sounds`.
- **Steal:** **temporal-core** (3 hooks on SessionStart + UserPromptSubmit +
  PreToolUse injecting `session_elapsed`, `time_since_last_action`, UTC). Simple,
  measurably helps time reasoning.
- **Skip:** claude-sounds (peon-ping already covers more events).
- https://github.com/rohitg00/awesome-claude-code-toolkit

### 4. VoltAgent/awesome-claude-code-subagents, topology, not agents
100+ subagents, 10 categories.
- **Steal:** the meta/orchestration category (dispatch -> verify -> merge handoff
  contract). Individual agent specs are commodity; overlaps my Workflow tool.
- https://github.com/VoltAgent/awesome-claude-code-subagents

### 5. pixelmojo.io "6 Production Patterns", one novel idea
Five are standard; the novel one is **Pattern #5: LLM semantic review on
PreToolUse(Edit)**, classify edit intent (auth/db/payment/rate-limit) and gate
high-risk domains with a Claude call. Maps onto my finance/trading repos as a
"this edit touches money, confirm" gate. Gotcha: per-edit LLM latency; batch-classify.
- https://www.pixelmojo.io/blogs/claude-code-hooks-production-quality-ci-cd-patterns

### 6. hesreallyhim/awesome-claude-code (46k), discovery lens only
Canonical index but mid-reorganization; hard to navigate today. Watch its Issues
for where the community is heading.
- https://github.com/hesreallyhim/awesome-claude-code

### Worth knowing (writeups + niche tools)
- JIT skill-activation hook (guarantee a skill loads on keyword match): https://claudefa.st/blog/tools/hooks/skill-activation-hook
- PreCompact memory evolution (Axis 3, with code): https://yuanchang.org/en/posts/claude-code-auto-memory-and-hooks/
- Routines / scheduled agents (Axis 6): https://www.mindstudio.ai/blog/claude-code-routines-scheduled-agents
- ccusage (token/cost CLI): https://www.npmjs.com/package/ccusage
- TechNickAI/claude_telemetry (`claude`->`claudia` wrapper, multi-backend): https://github.com/TechNickAI/claude_telemetry
- PHY041/claude-skill-citation-checker (bibliography only, not file:line): https://github.com/PHY041/claude-skill-citation-checker

---

## Adoption roadmap (living tracker)

Ranked by leverage-for-me x low-effort. Status updated as adopted.

| # | Item | Axis | Mechanism | Effort | Status |
|---|---|---|---|---|---|
| A | Prose-RAG index + UserPromptSubmit injector | 1 | fastembed (Air) + sqlite-vec + hook | M | not started |
| B | Hook-latency timing -> vps-mon | 2 | bash wrapper per hook | S | not started |
| C | Skill-usage weekly report | 2 | JSONL parse + launchd | S | not started |
| D | PreCompact auto-harvest -> ledger | 3 | PreCompact hook + Claude Haiku | M | not started |
| E | Citation / file:line Stop hook (Path A) | 5 | Stop hook, transcript parse | S | not started |
| F | Backlog-triage sweep | 6 | Routine / Hermes-agent | M | not started |
| G | Learning-capture nightly flush + synthesis | 3,6 | scheduled job | M | not started |
| H | Domain-fusion Stop->Notion (gated) | 4 | Stop hook + Notion MCP | M | not started |

Wiring + usage docs for each item are written here (or in the relevant
`tools/<name>/`) at adoption time, not before.

## Open decisions before building

- Item A: confirm the embedding model (default fastembed `bge-small`, on the Air)
  and corpus scope (til + research only, or include the vault); Voyage AI only if
  local quality is insufficient (sends private notes out, so opt-in).
- Item D/G: confirm the Claude Haiku harvest prompt + dedup against which stores.
- Item E: start non-blocking (log) vs blocking from day one.
- Item F/G: Routine (cloud) vs Hermes-agent (Mini) per minimum-infra rule.

---

## Round 2 (2026-06-15): the surface grew, and what shipped

Round-1 (above) said "there is no unused hook *event* left to light up." That is no longer
true: the Claude Code event surface roughly doubled in the Feb-Jun 2026 window. Verified
against current docs via the claude-code-guide agent.

### New hook events since round-1 (mostly untapped, by design)

UserPromptExpansion, PostToolBatch, StopFailure, MessageDisplay (transform/suppress assistant
text), WorktreeCreate / WorktreeRemove, FileChanged, CwdChanged, InstructionsLoaded,
ConfigChange, TaskCreated / TaskCompleted, TeammateIdle, Elicitation / ElicitationResult,
PostCompact, SubagentStart, PermissionDenied, Setup.

Brutal cut: for a solo operator only **WorktreeCreate/Remove, StopFailure, MessageDisplay**
matter; the rest serve agent-teams + MCP-form setups not in use. Do not chase the surface
for its own sake.

### New tools worth leaning on

| Tool | Use |
|---|---|
| **PushNotification** | desktop + phone push (mobile-first); `agentPushNotifEnabled`/`inputNeededNotifEnabled` are off by default |
| **Monitor** | reactive line-watch of a background command (CI, PR status, logs) instead of poll loops |
| **CronCreate / RemoteTrigger** | in-session + claude.ai-Routine scheduling (native, alongside launchd) |
| **LSP** | code/symbol navigation (def/refs/type); the code-search gap prose-rag punts |
| **Workflow** | named saved orchestrations (see `tools/cc-workflows`) |

### What shipped (mega-goal cc-elevation-r2)

Round-1's roadmap A-H plus the external "steal" list were ~80% delivered in the first wave.
Round 2 (this mega-goal) shipped most of the rest:

| Sub-goal | Tool / change | PR |
|---|---|---|
| 02 skills-map seed | cc-context-hooks JIT map 11 -> 69 keys / 48 skills | #275 |
| 03 prose-rag auto-inject | opt-in + recall gate (operational prompts ~0ms) | #277 |
| 04 worktree auto-provision | cc-worktree-provision (WorktreeCreate hook) | #278 |
| 05 saved workflows | cc-workflows (review-branch / research-sweep / cross-repo-sweep) | #280 |
| 06 scheduled intel | cc-intel (weekly digest + synthesis + repeat-detect) | #282 |
| 07 docs | this Round-2 section + the Monitor/LSP cheatsheet | (this PR) |
| 08 meta-agent | generate a subagent spec from a description | (pending) |
| 09 auto-lab-log | cc-harvest SessionEnd LAB_LOG draft | (pending) |
| 01 phone push | cc-notify | BLOCKED on Han (channel knob + live phone verify) |

First wave (round-1 build): cc-observe #261, cc-citation-guard #263, prose-rag #265,
cc-harvest #267, repo-sweep #268/#269, verify-claim #272, cc-money-gate #273,
cc-context-hooks #274.

External ideas now mapped to shipped tools: rohitg00 temporal-core -> cc-context (temporal);
JIT skill-activation -> cc-context (hints) + the #275 seed; pixelmojo #5 money gate ->
cc-money-gate; PreCompact memory evolution -> cc-harvest; ColeMurray OTel schema ->
cc-observe; Path-B adversarial verify -> verify-claim; Axis-1 prose RAG -> prose-rag;
disler meta-agent -> sub-goal 08.

### Cheatsheet: Monitor + LSP (two habits, not tools to build)

**Monitor** , reactive watching instead of a poll loop. Use when waiting on an external
state change (CI, a PR check, a deploy, a log line):

- Instead of looping `gh pr checks <pr>` + sleep, run `Monitor` on `gh pr checks <pr> --watch`
  (or `tail -f` a log) and let each new output line drive the next action.
- It uses Bash permission rules. Right for "wait until X, then react"; not for a one-shot read.

**LSP** , code/symbol navigation instead of grep-guessing. Use for "where is this defined /
what calls it / what is the type":

- `LSP` does jump-to-definition, find-references, type-info, symbol search, and call-hierarchy.
  Needs the code-intelligence plugin for the language.
- Complements prose-rag (prose) + codebase-memory (graph): LSP is the precise per-symbol layer.
  The prose-rag skill explicitly punts code search here.
