---
title: Process benchmark, does the SDD kit + prompt/handoff machinery pay for itself
date: 2026-07-02
purpose: Empirical benchmark of Han's working processes (dwarves-kit SDD pipeline, mega-goal planning layer, proof-of-done gate, prompt techniques, context handoffs, hook stack) against 30 days of session transcripts and 60 days of git history. Answers "significant impact or noise?" per component, with keep/simplify/drop verdicts. Use it to prioritize process trims and the coverage retrofit.
source_repos: [ops-toolkit, dwarves-kit, dfoundation, console-labs, hidden]
refresh_cadence: as-needed
next_review: 2026-10-01
status: active
---

# Process benchmark: impact vs noise (2026-07-02)

Question: is the process stack (SDD kit, mega-goals, proof gate, prompt improvement, handoffs, hooks) measurably helping a mostly-hands-off operator who cares about feature/test coverage, or would a simpler approach win?

Data: `cc-observe` over 30 days (7,890 transcripts), git forensics over 60 days (453 PR-shipped units on ops-toolkit main), a census of 326 specs across ops-toolkit + dwarves-kit, 57 mega-goal roadmaps across 5 repos, 90 tools' verification artifacts, and the kit's gate logs.

## Verdict table

| Component | Verdict | Key number |
|---|---|---|
| SDD kit flow on behavioral work | **Keep** | feat rework 8.0% (kit) vs 11.4% (direct), at ~3x change size |
| Proof-of-done gate | **Keep, close the override leak** | the ONE recorded override shipped the ONE post-gate revert (localterm, 9h to rollback) |
| Proof/test coverage across tools | **Gap, retrofit** | 36% of 90 tools have proof AND tests; 29 have neither (~20 first-party) |
| Mega-goal planning layer | **Keep, trim the habit** | 67% of 57 mega-goals fully complete; 79% of 348 sub-goals done |
| Spec ceremony volume (ops-toolkit) | **Simplify** | June: 153 specs written, 24% shipped; 84 specs parked at validated |
| handoff skill | **Drop / fold into mega-goal pointer** | 1 use in 30 days; ROADMAP+POINTER_PROMPT is the real handoff and it converts |
| prompt-improver | **Keep** | 60 fires, 0 errors, cheap; it is a deliberate learning rule |
| slop-cleaner Stop hook | **Fix or drop** | 8,483 runs x 496ms p50 (~70 min/month), re-flags the same 7 files every stop, never resolves |
| Stop-hook stack overall | **Trim** | ~2.3 h/month p50 wall-clock across 5 hooks (slop-cleaner + session-state-save + 3 style guards) |
| Standing context | **Already being attacked (token-optim series)** | ~25-35k tokens of instructions per session start (global CLAUDE.md ~7k words + 103 skills + ponytail/superpowers) |
| Broken/high-error tools | **Fix** | notion-query-data-sources 94% error rate (15/16); ExitWorktree 13%; playwright browser_navigate 27% |

## 1. The SDD kit is not noise; it earns its cost exactly where the risk is

60-day cohort forensics on ops-toolkit main (453 shipped units; KIT-FLOW = diff carries SPEC/proof/verification artifacts, DIRECT = plain commits):

| Cut | KIT | DIRECT |
|---|---|---|
| Raw rework rate (>=1 day later fix/revert on same tool path) | 6.3% (16/254) | 2.5% (5/199) |
| Behavioral units only (>=1 non-md file) | 7.2% | 6.6% |
| feat+refactor units only | **8.0%** (14/174) | **11.4%** (4/35) |
| Median files per unit | 9 | 3 |
| Same-day iteration (review fixups) | 34 units | 11 units |

The raw rate favoring DIRECT is a composition artifact (59% of direct units are docs/housekeeping with nothing to rework). Like-for-like, kit-shipped features absorb equal-or-lower post-ship rework while being ~3x larger, and the kit visibly front-loads churn into same-day review fixups, which is the ceremony doing its job. Caveats: the DIRECT feat sample is small (n=35), and rework hotspots in BOTH cohorts are host-coupled deploy tools (vps-mon, substrate, hermes, dictate, md-preview) where the host's reality, not the spec, is the failure mode.

Causal sample for the gate itself: the single proof-gate override in the ledger (2026-07-01T17:19Z, rtk-611-update batch) explicitly declared "the localterm auth-gate source change is NOT separately re-proofed". That exact change failed on real hosts and was reverted 9 hours later (#618), with the revert verified by the gate's own shape (green exit 0, negctl exit 3). One data point, but it is a clean one: the gate catches what it gates; the override path is where regressions leak.

## 2. The coverage gap is the real problem, not the process

Han's stated priority is feature/test coverage, and this is where the numbers are weakest:

- 90 tools in ops-toolkit; 53% have `docs/proof-of-done.md`, 50% have any tests, **36% have both, 32% have neither**.
- The neither-list (29) after discounting ~9 third-party deploy bundles leaves ~20 first-party tools with zero verification artifacts: rtk, llm-bench, tg-cleanup, notion-sync, wisp, vn-invoice, bot-fleet, cloud-estate-cleanup, mac-backup (manual restore-tests.md only), etc.
- The done-gate marker is repo-wide but in practice only bites tools that already opted in. The process is sound; its coverage is opt-in.

Highest-leverage single action from this whole benchmark: a retrofit mega-goal that walks the first-party neither-list and lands a minimal proof-of-done + one runnable check per tool.

## 3. Mega-goal layer converts; spec layer over-produces

Mega-goals (57 roadmaps, ~all started within 30 days): 38 fully complete (67%), 274/348 sub-goals done (79%), typical plan-to-done inside the same wave. The planning layer is consumed, not hoarded. Two waste patterns:

- **Pre-scaffolded successors**: 8 untouched roadmaps + 4 roadmap-less folders, all 9+ days stale except kit-hardening (created today). Scaffolding the NEXT mega-goal before the current closes creates dead inventory (safari-lab, safari-net-complete, dictate-overlay, cf-quota-tracker, icy-mint-burn duplicated across two repos).
- **Series fragmentation**: cc-elevation r1-r4, six dictate-* goals, nine safari-* goals, five vibe-dex-* goals. Each converts, but one initiative burns 4-9 plan-for-mega-goal invocations (most of the 45 fires/30d).

Specs are the opposite story in ops-toolkit: 238 specs in ~60 days; May cohort 55% shipped, **June cohort 153 specs and only 24% shipped**, 84 specs parked at validated/accepted (dictate SPEC-010..020, homelab-net-research's 6, vibedex pile). Some is status-flip lag from retroactive-SDD habits, but June tripled spec volume while shipping less of it. dwarves-kit itself is healthy (61% shipped; June cohort 83%), so the loop closes where the kit governs its own repo; the over-production is an ops-toolkit habit.

## 4. The funnel-drop illusion (measurement note)

cc-observe shows kit:spec 21 + kit:spec-validate 29 but kit:execute 5 / kit:verify 3 / kit:ship 2, which looks like ceremony without execution. It is mostly a measurement artifact: execution runs through /goal loops driven by mega-goal POINTER_PROMPTs (visible as dozens of inline-echo UserPromptSubmit hooks, some firing 30-50 times), not through the kit:execute skill. Judge execution by shipped units (453 in 60 days) and mega-goal completion (79%), not skill-invocation counts.

## 5. Hook and context tax

Per-event Stop-hook cost over 30 days (p50 math, tails are worse, p95 up to ~5s each):

| Hook | Runs | p50 | ~wall-clock/30d |
|---|---|---|---|
| slop-cleaner.sh | 8,483 | 496ms | ~70 min |
| session-state-save.sh | 8,483 | 271ms | ~38 min |
| em-dash-fix.sh | 4,929 | 148ms | ~12 min |
| show-without-run-guard.sh | 4,929 | 126ms | ~10 min |
| secret-guard-stop.sh | 4,929 | 102ms | ~8 min |

slop-cleaner is the standout: it runs a `find` over the tree on every Stop, and its log shows it flagging the SAME "7 files" every few minutes for days (19 consecutive identical entries), i.e. a nudge that is never acted on, re-injected into context every turn. Either give it resolution memory (flag once per file per session) or drop it. session-state-save at every Stop may be over-frequent for its purpose too.

Standing context: ~25-35k tokens of instructions load before any task input (global CLAUDE.md ~7k words, 103 skill descriptions, ponytail + superpowers session-start injections, repo CLAUDE.md). The token-optim-v2/v3 mega-goals already attack this; this benchmark just confirms it is the right target. A live false-positive observed during this very session: the "you are implementing a SPEC" UserPromptSubmit reminder fired repeatedly in a pure analysis session.

Tool errors worth one fix each: mcp notion-query-data-sources 94% (15/16, effectively broken), playwright browser_navigate 27%, ExitWorktree 13%, AskUserQuestion 10% (542 calls/month is also a real interaction load for a hands-off operator; the grill/brainstorm interview layer is where it concentrates).

## 6. Handoffs

The `handoff` skill fired once in 30 days. The de-facto handoff mechanism is the mega-goal ROADMAP + POINTER_PROMPT + goal registry, and its 79% sub-goal completion says cross-session continuity works without a separate ceremony. Fold the skill's intent into the mega-goal docs and stop maintaining it as a separate path.

## Ranked actions

1. **Coverage retrofit mega-goal**: minimal proof-of-done + one runnable check for the ~20 first-party tools with neither. Directly serves the stated priority.
2. **Fix or drop slop-cleaner**; audit session-state-save frequency. Biggest pure-tax item.
3. **Tighten the proof-override rule**: an override may not cover source/behavioral changes, only inert docs/deploy-bundle items (the localterm sample is the argument).
4. **Stop pre-scaffolding successor mega-goals**; park or delete the 8 untouched roadmaps + 4 empty folders.
5. **Spec discipline in ops-toolkit**: a spec only when there is a gate it will hit; flip or close the 84 validated-parked specs (or accept them as documentation and mark them so).
6. **Drop the handoff skill** (fold into mega-goal pointer docs).
7. **Fix notion-query-data-sources** or remove it from the loadout.

## Bottom line

The core loop (SDD on behavioral work + proof gate + mega-goal roadmaps) has measurable positive impact and should stay: it delivers equal-or-lower rework on 3x-larger changes, front-loads churn to same-day, and its one bypass produced its one regression. The noise is peripheral and specific: spec over-production in June, pre-scaffolded dead roadmaps, a Stop hook that re-nags without resolution, a near-dead handoff skill, and a 25-35k-token standing preamble. Simplify the periphery; do not swap the core for a simpler approach, because the risk profile (hands-off operator, large autonomous changes) is exactly where the data says the ceremony pays.
