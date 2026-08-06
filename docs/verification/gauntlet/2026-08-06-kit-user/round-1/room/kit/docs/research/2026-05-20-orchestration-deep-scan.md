---
title: Orchestration / workflow-enforcement deep scan (the inspired repos vs WORKFLOW.md)
date: 2026-05-20
source: web scan of inspired-repo current HEADs + harness-engineering literature; builds on ops-toolkit/research/2026-05-20-agent-workflow-enforcement-patterns.md
feeds: SPEC-006 (the orchestration spine)
benchmarked_against: WORKFLOW.md (shipped this cycle), SPEC-003 (orchestration layer), docs/PHILOSOPHY.md
status: active
---

# Orchestration deep scan

This goes one layer deeper than the prior enforcement-taxonomy note. That note asked "how do instruction files make a stochastic agent comply?" and answered with a 9-row taxonomy. This scan asks the SPEC-006 question: **now that WORKFLOW.md ships, is there any orchestration mechanism in the inspired set worth absorbing, and does it survive the PHILOSOPHY NO-list?** Every repo was checked at its current HEAD (May 2026), not at the version the kit originally pattern-matched.

The honest headline up front: WORKFLOW.md is competitive as a *readable spine*, and the kit's verification pipeline is still the strongest enforcement mechanism in the field. The scan found exactly two patterns worth absorbing, both of which sharpen what the kit already has rather than adding a new layer.

---

## TL;DR

- **WORKFLOW.md is competitive.** As a single readable spine that names phases, routes by risk, and points each gate at an existing guardrail, it is at parity with harness-experimental's `AGENTS.md` and ahead of every persona-driven competitor (gstack, CCGS, BMAD) on honesty: it does not claim prose enforces.
- **The kit's moat held up.** The whole field converged on the kit's exact verify shape (worker → verifier → fix), and Anthropic's own SDK guidance endorses it (rules/code > visual > LLM-as-judge). GSD, Shipyard, harness-experimental, multi-agent-ralph all now ship a read-only verifier subagent. The kit was early, not behind.
- **ADOPT (1): a decision-translation gate.** GSD's strongest 2026 addition: decisions locked at think/spec time get named IDs (D-07 style) and a check *refuses to advance* until each appears in the plan artifact. This is the "decision records the next agent inherits" idea from the prior note, now hardened into a mechanism. The kit has the spec-drift-guard hook shape to host a lightweight grep version. **Feeds SPEC-006.**
- **ADAPT (1): the in-session Stop-hook loop is now first-party-blessed.** Anthropic's official `ralph-wiggum` plugin implements the Ralph loop **inside the session via a Stop hook, not an outer bash loop**. This directly validates the kit's anti-rationalization-as-Stop-hook architecture and means PHILOSOPHY §3's "outer loop = autonomous-runtime, decline" is too blunt: a bounded in-session continuation loop is architecturally native to the kit. Worth a PHILOSOPHY footnote, not a feature yet. **Feeds SPEC-006 framing.**
- **REJECT (most of it).** Persona theater (BMAD "STAY IN CHARACTER", gstack CEO/Designer roles, CCGS 49-agent studio), CAPS coercion prose (BMAD "NO LYING OR CHEATING", superpowers `<EXTREMELY-IMPORTANT>`), hard phase gates (Spec Kit/BMAD HALT), and vendor-skill sprawl (ClaudeKit, OMC at 36 skills) are all explicit PHILOSOPHY rejections and stay rejected. Nothing new changed that calculus.
- **The risk-tier table is validated, not improved-upon.** harness-experimental's lane model is the source the kit already cited; nobody in the field does work-sizing better. GitHub's Always/Ask-First/Never boundary pattern (60k AGENTS.md repos) is a *permission* taxonomy, not a *process-weight* taxonomy, so it is orthogonal, not a replacement.
- **Net for SPEC-006: do less, not more.** The spine exists. The one net-new mechanism worth building is the decision-translation check, and it should be the lightest possible grep-grade guardrail, not a staged-gate machine. Everything heavier (GSD's 5-gate staged architecture, Shipyard's STATE.json state machine) trades the kit's "readable in 30 seconds" property for enforcement the kit already gets cheaper from its verifier.

---

## Per-repo findings table

| Repo (HEAD checked) | Orchestration approach | Enforcement mechanism (taxonomy row) | Gap vs WORKFLOW.md | Verdict |
|---|---|---|---|---|
| **hoangnb24/harness-experimental** (v0, 6 commits) | `AGENTS.md` source-of-truth hierarchy + task loop + tiny/normal/high-risk lanes + `decisions/` the next agent inherits | Forced state-file re-read + risk-tiered routing + confirmation gates (prose) | The risk-tier source the kit already absorbed; adds `decisions/` durable-record idea | ADAPT (decisions idea → see GSD, same pattern hardened) |
| **GSD / get-shit-done** (v1.42.1, ~55k★, 29 skills/12 agents/2 hooks) | Thin-orchestrator routes to namespaced skills; staged discuss→plan→execute→verify→ship | **Decision-translation gate** (blocking at plan, advisory at verify); Nyquist gate (no verify-command → plan rejected); plan-checker + verifier subagents; 2 JS hooks (read-before-edit, workflow-guard) | Has named-decision enforcement the kit lacks; far heavier (86 skills, JS hooks, state files) | **ADOPT** the decision-gate idea; REJECT the weight |
| **gstack** (Garry Tan, 23 tools) | Persona pipeline: /office-hours → /plan-ceo-review → /plan-eng-review → /review → /qa → /ship | Persona prose ("CEO", "Eng Manager") + per-command checks | Persona theater; no honest enforcement claim | REJECT (persona) |
| **ClaudeKit** (mrgoonie/claudekit-skills) | Skill catalog (adversarial-review, sequential-thinking, etc.) | Per-skill prose; verification-gate skill ("evidence before status") | Vendor-skill sprawl; no single spine | REJECT (sprawl); the "evidence before status claim" idea the kit already has via anti-rationalization + completion contract |
| **Context Hub** (andrewyng) | Not an orchestrator; API-docs retrieval product | n/a | Orthogonal (the kit depends on it via get-api-docs skill) | REJECT (out of scope; already a dependency) |
| **oh-my-claudecode (OMC)** (19 agents/36 skills) | Teams-first multi-AI orchestration (Claude+Gemini+Codex); HUD; ai-slop-cleaner | Multi-agent dispatch + hooks library | UI-shell creep + vendor sprawl; multi-runtime is out of the kit's scope | REJECT (PHILOSOPHY §2 UI-shell; multi-agent is L5) |
| **CCGS (Claude-Code-Game-Studios)** (49 agents/72 skills) | Studio hierarchy (directors/leads/specialists) + Collaborative Design Protocol (Question→Options→Decision→Draft→Approval) + /start router + path-scoped rules | Persona prose + per-tool ask-before-write protocol | Persona theater at extreme scale; the /start router + path-scoped rules + CDP the kit already absorbed | REJECT new (persona); already absorbed the useful 3 |
| **Smart Ralph** (tzachbon) + **ghuntley/ralph** | Outer bash `while` loop re-injecting PROMPT.md; fix-agent fail-fix-re-verify; self-updating AGENT.md | **Outer loop = the enforcement** (process restart with fresh context) | The kit absorbed fix-agent already; outer loop is autonomous-runtime | REJECT outer loop (PHILOSOPHY §3); already have fix-agent |
| **Anthropic ralph-wiggum plugin** (first-party, in anthropics/claude-code) | Ralph loop **in-session via a Stop hook**, not bash; `--completion-promise` string match + `--max-iterations` cap | **Stop hook intercepts exit, re-injects same prompt** | First-party proof the kit's Stop-hook architecture is the blessed loop substrate | **ADAPT** (validates kit architecture; PHILOSOPHY footnote) |
| **github/spec-kit** (v0.8.11, 104k★) | constitution→specify→clarify→plan→tasks→implement; +`/analyze` (cross-artifact consistency) +`/checklist` (2026) | Hard STOP gates ("If checklist incomplete... STOP and ask"); externalized constitution.md rule set; "max 3 iterations" loops | Hard phase gates (explicit PHILOSOPHY reject); `/analyze` cross-artifact check is interesting but heavy | REJECT gates; note `/analyze` as a future docs-drift idea (the kit's /docs already covers) |
| **bmad-code-org/BMAD-METHOD** (v6, ~48k★) | Named-agent personas (Mary/Amelia) + YAML workflow blueprints; develop-story order-of-execution | Identity reprogramming ("STAY IN CHARACTER") + anti-deception CAPS ("NO LYING OR CHEATING") + MANDATORY elicitation | Persona + coercion; the exact ~70-85% guidance ADR-0008 rejected | REJECT (persona + CAPS) |
| **Cline Memory Bank** | 6-file memory bank; "read ALL files at start of EVERY task"; named "update memory bank" trigger | **Forced state-file re-read** + identity framing ("memory resets between sessions") | Re-read discipline the kit gets from CLAUDE.md auto-load + spec-as-required-reading; identity framing is persona-adjacent | REJECT (the kit's re-read is native; no Memory Bank file sprawl) |
| **AGENTS.md standard** (Agentic AI Foundation / Linux Foundation, 60k+ repos) | "README for agents"; nearest-file-wins precedence | Deliberately NOT an enforcement engine; only guarantee = "run programmatic checks before finishing" | The kit's WORKFLOW.md *is* the AGENTS.md-pattern adaptation, delivered via CLAUDE.md | REJECT filename (Alt C, already decided); pattern already absorbed |
| **Shipyard** (lgbarn, v4.7.0, 57★), *new entrant* | idea→/brainstorm→/plan→/build→/ship; STATE.json state machine; verifier.md (haiku); parallel-dispatch | Blocking: two-stage review + security audit + TeammateIdle/TaskCompleted hooks; `--light` skips gates | Near-clone of the kit's thesis with a state machine; verifier is the same pattern; heavier, fewer stars | REJECT (no new pattern; confirms convergence) |
| **multi-agent-ralph-loop** (alfredolopez80), *new entrant* | 4-stage quality gates, 22 hooks, MemPalace 4-layer memory, 6-teammate Agent Teams | Many hooks + parallel teams + memory stack | Maximalist; opposite of "readable in 30 seconds" | REJECT (anti-PHILOSOPHY scale) |

---

## Deep dives (ADOPT / ADAPT only)

### ADOPT: GSD's decision-translation gate (the one net-new mechanism worth building)

GSD v1.40+ added the strongest enforcement idea the scan found that the kit does **not** already have. During its discuss/plan phases, every implementation decision gets a stable identifier (cited as `D-07` etc.), and GSD "refuses to mark the phase planned until every trackable decision appears in at least one plan's `must_haves`, `truths`, or body." At verify time the same check runs but only warns. GSD names the asymmetry deliberately: *"the blocking gate is cheap at plan time but hostile at verify time."*

Why this is better/more complete than what the kit has: the kit's spec already carries a Decision Log (DEC-001…DEC-013 in SPEC-003), and the verifier checks acceptance criteria, but **nothing checks that the decisions made in /think or /spec actually survived into the task breakdown the worker executes.** That is the exact gap the prior research note flagged ("decision records the next agent inherits; neither Spec Kit nor superpowers emphasize it"). GSD turned that note into a checkable gate. It is the institutional-memory mechanism, hardened.

How it lands in the kit (the minimal version): the kit already ships `spec-drift-guard.sh`, a hook that greps the spec's declared file manifest and warns on out-of-manifest writes. A decision-translation check is the same shape pointed at a different target: grep the spec for `DEC-NN` / `D-NN` identifiers in the Decision Log, then assert each appears somewhere in the Task Breakdown section. Bash + grep, sub-500ms, one-sentence-describable ("warns when a spec records a decision that no task references"), source-cited to GSD. It must be a **warn, not a block** (Detect-don't-dictate), which actually matches GSD's own verify-time posture, not its plan-time block. This is a SPEC-006 candidate, scoped to a single new guardrail or a WORKFLOW.md completion-contract clause, not a staged-gate machine.

### ADAPT: the in-session Stop-hook loop is first-party-blessed (reframes PHILOSOPHY §3)

The prior note and SPEC-003 both treated "the outer bash `while` loop" as the canonical Ralph mechanism and declined it as "autonomous-runtime territory, route to GSD v2 / OMC." That framing is now outdated by a first-party fact: **Anthropic's own `ralph-wiggum` plugin (shipped inside `anthropics/claude-code`) implements the loop in-session via a Stop hook, not an outer bash loop.** Its README is explicit: *"The loop happens inside your current session - you don't need external bash loops,"* and *"This plugin implements Ralph using a Stop hook that intercepts Claude's exit attempts."* Completion is an exact-string `--completion-promise` plus a `--max-iterations` safety cap.

Why this matters for the kit: dwarves-kit already runs the anti-rationalization Stop hook, which intercepts premature exit. That is structurally the same primitive Anthropic uses for ralph-wiggum, minus the re-inject-and-continue behavior. So the kit is not "missing the loop layer that lives in a different tool"; the kit owns the substrate the blessed loop is built on. SPEC-003's DEC-005 ("outer loop declined, autonomous-runtime territory") is correct about the *unbounded outer bash loop* but too blunt as written, because it implies loops are off-limits when the in-session bounded version is native and first-party.

How it lands: not a feature this cycle (no signal that the kit needs autonomous continuation; the kit's thesis is one bounded session with verification). It lands as a **PHILOSOPHY framing correction**: distinguish "unbounded outer bash loop" (still declined, autonomous-runtime) from "bounded in-session Stop-hook continuation" (architecturally native, first-party-blessed, available if a real need appears). This keeps the rejection honest and prevents a future reader from re-litigating it from scratch. SPEC-006 should cite ralph-wiggum when it explains why the kit's enforcement is Stop-hook-shaped.

---

## Absorb plan (prioritized)

| # | Recommendation | PHILOSOPHY principle satisfied | NO-list gate it passes | Kit artifact touched | Feeds |
|---|---|---|---|---|---|
| 1 | **Decision-translation check.** A grep-grade guardrail (or a WORKFLOW.md completion-contract clause) that warns when a Decision-Log entry (`DEC-NN`) has no referencing task in the spec. Warn-only, never block. | "Guardrails over guidance" (mechanism, not prose); "Verify before proceeding" (closes the think→build decision-loss gap); "Detect, don't dictate" (warn, matching GSD's verify-time posture) | No binary (bash+grep); no LLM API; <500ms; one-sentence-describable ("warns when a spec records a decision no task references"); source-cited (GSD v1.40+); serves Spec+Build+Review phases | New hook `decision-drift-guard.sh` (mirrors spec-drift-guard) OR a WORKFLOW.md completion-contract line + a `tests/test-meta.sh` assertion. Prefer the lighter of the two. | **SPEC-006** |
| 2 | **PHILOSOPHY §3 loop-framing correction.** Split "outer loop" into unbounded-bash (declined) vs bounded in-session Stop-hook (native, first-party-blessed). Cite Anthropic ralph-wiggum. | "Synthesize, don't originate" (now has a first-party source); honesty of the NO-list | Doc-only; no new component; source-cited | `docs/PHILOSOPHY.md` §3 (one paragraph) + SPEC-006 background. No code. | **SPEC-006** framing / standalone doc edit |
| 3 | **Confirm the risk-tier table needs nothing.** Re-affirm harness-experimental lanes as the cited source; note GitHub's Always/Ask-First/Never is a permission taxonomy (orthogonal), not a process-weight upgrade. No change. | "Synthesize, don't originate" (source still valid) | n/a (no change) | None (a one-line note in SPEC-006's prior-art section) | standalone |

Recommendation 1 is the only build. Recommendations 2 and 3 are doc/framing. If SPEC-006 wants to ship the absolute minimum, it can fold #1 into WORKFLOW.md's completion contract as a self-check clause and skip the new hook until a retro shows decisions actually getting dropped (PHILOSOPHY §5's "1 week on a real project, with signal" bar). That is the more conservative, more PHILOSOPHY-faithful path; the hook is the version to build only if the prose version proves insufficient.

---

## What we should NOT absorb (and why)

| Tempting pattern | Where seen | Why rejected |
|---|---|---|
| **Hard phase gates / HALT** ("STOP and ask, wait for user response") | Spec Kit `implement.md`, BMAD, agent-os | Verbatim PHILOSOPHY rejection: *"Decision this would reject: add a phase-locking system that blocks /execute unless /spec-validate has been run. Rigid phase gates annoy experienced coders."* Hard stops stay reserved for irreversible cost (rm-rf, push-to-main, premature done, failed verify). |
| **Persona theater** (named agents, studio hierarchy, "STAY IN CHARACTER") | BMAD (Mary/Amelia), gstack (CEO/Designer), CCGS (49-agent studio) | PHILOSOPHY "What we explicitly reject" #3 (agent-persona theater) + ADR-0008. Agents are named for function (task-verifier, fix-agent), never persona. Identity framing implies capability the mechanism lacks. |
| **Coercion CAPS prose** ("NO LYING OR CHEATING", `<EXTREMELY-IMPORTANT>`, "DO IT OR I WILL YELL AT YOU") | BMAD v6, superpowers, ghuntley/ralph | This is the ~70-85% guidance ADR-0008 chose hooks over. WORKFLOW.md is openly guidance-grade and points at the hook that actually enforces; it does not pretend prose coerces. |
| **Vendor-skill sprawl** (catalog grows release over release) | ClaudeKit, OMC (36 skills), CCGS (72 skills) | PHILOSOPHY "What we explicitly reject" #1 + NO-list one-sentence rule + "serves 2+ phases" gate. A skill that pads the catalog is rejected. |
| **UI-shell creep** (HUD with caches, themes, multi-runtime config) | OMC HUD, multi-agent-ralph (22 hooks) | PHILOSOPHY "What we explicitly reject" #2 + "Bash over binaries / readable in 30 seconds". Statusline carve-out is display-only. |
| **Unbounded outer autonomous loop** (`while :; do cat PROMPT.md \| claude-code; done`) | ghuntley/ralph, Smart Ralph, ralphy, ralphex | PHILOSOPHY §3 (autonomous-runtime, route to GSD v2 / OMC). The kit is one bounded session. NOTE the nuance from Deep Dive 2: the *bounded in-session Stop-hook* version is fine and first-party; only the unbounded bash loop is declined. |
| **Multi-agent / Agent-Teams parallel orchestration** | OMC, Shipyard teams mode, multi-agent-ralph (6 teammates), GSD wave execution | PHILOSOPHY §2: multi-agent across parallel sessions is L5 (Nimbalyst/Conductor). The kit dispatches subagents sequentially within one session by design. |
| **Memory-Bank file sprawl + identity re-read framing** | Cline Memory Bank (6 files), BMAD `_bmad/` | The kit's re-read discipline is native (CLAUDE.md auto-load + spec-as-required-reading). Six bespoke memory files is the indirection WORKFLOW.md's "One source of truth" deliberately avoids. |
| **State-machine progression engine** (STATE.json gating phase transitions) | Shipyard, GSD phase state files | Trades "Detect, don't dictate" for a controller that owns progression. The kit detects state (context-readiness) and suggests; it never owns a blocking state machine. |

---

## Sources (fetched 2026-05-20)

- hoangnb24/harness-experimental AGENTS.md + repo tree: https://github.com/hoangnb24/harness-experimental ; https://raw.githubusercontent.com/hoangnb24/harness-experimental/main/AGENTS.md
- GSD / get-shit-done USER-GUIDE (gate types, decision-translation gate, Nyquist, plan-checker, verifier, 2 hooks): https://github.com/gsd-build/get-shit-done/blob/main/docs/USER-GUIDE.md ; https://github.com/gsd-build/get-shit-done/
- Anthropic ralph-wiggum plugin (in-session Stop-hook loop, first-party): https://github.com/anthropics/claude-code/blob/main/plugins/ralph-wiggum/README.md
- ghuntley/ralph (outer-loop technique, 2026 subagent-parallelization update): https://ghuntley.com/ralph/
- github/spec-kit v0.8.11 (constitution→implement, STOP gates, +/analyze +/checklist): https://github.com/github/spec-kit
- bmad-code-org/BMAD-METHOD v6 (personas, anti-deception CAPS, _bmad folder): https://github.com/bmad-code-org/BMAD-METHOD ; https://docs.bmad-method.org/explanation/named-agents/
- Cline Memory Bank (forced re-read discipline): https://docs.cline.bot/prompting/cline-memory-bank
- AGENTS.md standard (README-for-agents, nearest-file-wins, Agentic AI Foundation / Linux Foundation, 60k repos): https://agents.md
- gstack (Garry Tan, 23-tool persona pipeline): https://github.com/garrytan/gstack
- Donchitos/Claude-Code-Game-Studios (Collaborative Design Protocol, /start router, path-scoped rules, 49 agents): https://github.com/Donchitos/Claude-Code-Game-Studios ; https://github.com/Donchitos/Claude-Code-Game-Studios/blob/main/CLAUDE.md
- Yeachan-Heo/oh-my-claudecode (teams-first multi-AI, HUD, slop-cleaner, 19 agents/36 skills): https://github.com/Yeachan-Heo/oh-my-claudecode
- mrgoonie/claudekit-skills (skill catalog, adversarial-review, verification-gate): https://github.com/mrgoonie/claudekit-skills
- tzachbon/smart-ralph (fix-agent fail-fix-re-verify): https://github.com/tzachbon/smart-ralph
- lgbarn/shipyard v4.7.0, NEW ENTRANT (lifecycle plugin, verifier.md, STATE.json, blocking review gates): https://github.com/lgbarn/shipyard
- alfredolopez80/multi-agent-ralph-loop, NEW ENTRANT (4-stage gates, 22 hooks, MemPalace memory): https://github.com/alfredolopez80/multi-agent-ralph-loop
- Harness-engineering literature (PEV pattern, three-layer architecture, GitHub Always/Ask-First/Never boundary; term attributed to Mitchell Hashimoto Feb 2026 / OpenAI Ryan Lopopolo Feb 11 2026): https://www.augmentcode.com/guides/harness-engineering-ai-coding-agents ; https://www.abhishek-tiwari.com/agent-guardrails-action-gates-harnesses-and-governance-four-layers-four-different-jobs/

### Not found / nothing relevant
- **"Context Hub" as an orchestrator:** confirmed it is an API-docs retrieval product (andrewyng/context-hub), not a workflow/orchestration layer. The kit already treats it as a dependency via the get-api-docs skill. No orchestration finding.
- **"OMC" name ambiguity:** the architect-verifier lineage the kit once attributed to "OMC" does not trace to `1mancompany/OneManCompany` (a pixel-art agent-company OS = persona theater, already rejected in SPEC-002 TASK-4). The verify pattern is correctly owned as synthesized. No new finding; lineage already corrected.
- **A "better than WORKFLOW.md" spine:** none found. Every competitor is either at parity (harness-experimental, AGENTS.md standard) or trades the kit's honesty/readability for persona prose, CAPS coercion, hard gates, or a state-machine engine.
