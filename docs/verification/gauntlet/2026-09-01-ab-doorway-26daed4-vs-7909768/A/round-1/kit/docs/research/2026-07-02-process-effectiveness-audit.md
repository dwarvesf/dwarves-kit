---
title: Process-effectiveness audit (prompt technique / SDD framework / dispatched context)
date: 2026-07-02
purpose: Answers "do my processes have significant impact, or do they introduce noise better swapped for something simpler?" (Tom's judge prompt, run properly). Three independent miners over RAW data (JSONL transcripts, mega-goal records, merged-PR diffs, gate ledgers); cc-observe deliberately not used. Holds the verdict per layer, the keep/fix/kill list, and the full miner evidence.
source_repos: [ops-toolkit, dwarves-kit]
---

# Process-effectiveness audit, 2026-07-02

Question (Han, via Tom's framing): I am mostly hands-off on reading the code but anal about feature and test coverage. Do my processes (VCC-style handoff prompts, the mega-goal -> V-model SDD framework, subagent dispatch) have significant impact, or do they introduce noise and inefficiency better swapped for a simpler approach?

Method: three parallel fresh-context miners over raw sources, no reliance on Han-built summary tooling (cc-observe distrusted by request). Miner A: token economics from 13 session JSONLs (deduped by message.id). Miner B: catch-vs-ceremony evidence from mega-goal NOTES/FEEDBACK/retros/ledgers. Miner C: process-overhead ratios from the 10 most recent merged PRs per repo.

## Verdict per layer

| Layer | Verdict | Core evidence |
|---|---|---|
| Review stack (spec-validate, fresh-context review, review-team, gates) | **KEEP, it earns its cost** | Commit-hashed catches at every layer; each layer catches what the previous structurally cannot; 7 push blocks + 5 safety blocks in ~36h prove the hooks bite |
| Specs + BACKLOG | **KEEP** | Real programmatic consumers (spec-index.sh, backlog.sh, task-verifier verifies against spec ACs, board cockpit) |
| task-verifier alone | **WEAKEST REVIEW LINK** | Multiple recorded cases where task-verifier AND integration-checker rubber-stamped a defect only /review caught ("a 'replace' task that left both copies passed two independent verifiers") |
| LAB_LOG + impl-notes | **CEREMONY (write-only)** | Hooks check diff PRESENCE, never content; no programmatic reader; ~8 generic citations repo-wide; sole content consumer is the human-invoked narrate-log |
| proof-of-done | **FORCING FUNCTION, not a document** | Read exactly once by the ship-gate at the push it justifies (5 proof-gate blocks prove it bites); no evidence anyone re-reads a 136K proof post-merge |
| Gate run-ledger | **CEREMONY as built** | Only 1 surviving run record; all 11 gate rows blanket-overridden with one pasted reason; entire pre-July ledger wiped by the 2026-07-01 plugin reinstall (telemetry that does not survive reinstall cannot feed retro) |
| HANDOFF/DECISIONS (VCC handoff) | **UNPROVEN, dead-letter so far** | Mandated 2026-06-29; zero files ever produced, zero orchestrated runs (orchestrate.sh + handoff_gen.py built-and-tested, never production-run); one ad-hoc stale handoff actively misled a sub-goal (vps-mon writebook, rework PR #452) |
| FEEDBACK.md channel | **MOSTLY DEAD** | Same cross-repo worktree friction logged 3x over 9 days, zero fix; NOTES Proposed-additions DO get consumed (one became the kit-hardening mega-goal) |
| Subagent dispatch (fresh-context) | **CHEAP, keep dispatching** | 30 dispatches = 1.0% of output, 4-11% of session tokens even in dispatch-heavy sessions; median dispatch ~= 1.2x one main-thread human turn of fresh input. Tom's "3x" applies to context-INHERITING forks; zero were run |
| Session length / cache-read | **THE ACTUAL COST CENTER** | 772M cache-read vs 1.59M uncached input (485:1); one 606-call session re-read 238M tokens; re-read churn (same file read 21x) |
| Hooks/attachments + skills | **ACCEPTABLE** | Attachment overhead 3-11% of fresh input (upper bound); skill fires 17/18 with follow-through (~6% ignored) |
| Non-Anthropic router models in long sessions | **AVOID** | GLM-5.2 session: zero caching, 601K uncached input (9x any Claude session) |

## The three-layer answer

1. **Prompt technique (VCC handoff): unmeasurable, because it has never run.** The whole two-tier HANDOFF/DECISIONS contract exists only in templates and orchestrate.sh; the kit-hardening run will be its FIRST production exercise. Instrument that run; do not conclude anything about the technique yet.
2. **Framework (V-model SDD): the review half has significant, documented impact; the diary half is noise.** Keep the layered reviews and gates. The bookkeeping bifurcates cleanly into consumed (specs, backlog, proof-as-gate-token) and write-only (LAB_LOG content, impl-notes, run-ledger). ops-toolkit's median merged PR is 83.8% process lines and 5/10 recent PRs were pure bookkeeping about other PRs; dwarves-kit (bookkeeping rides inside feature PRs) runs 34.9%.
3. **Dispatched context: dispatch is not the cost problem; session length is.** Fresh subagents are cheap and the review-stack evidence says fresh context is exactly where the catches come from. The lever is context hygiene in long sessions (avoid re-reads, split mega-sessions), not avoiding dispatch.

## Recommended moves (impact-ordered)

1. **Trim the write-only diary layer.** LAB_LOG entries to one line (the hook only checks presence anyway); drop impl-notes for non-spec work; kill or fold FEEDBACK.md into NOTES Proposed-additions (the one channel proven to be read).
2. **Stop minting pure-bookkeeping PRs.** Adopt the dwarves-kit pattern repo-wide: bookkeeping rides inside the feature PR. 5/10 recent ops-toolkit PRs need not have existed.
3. **Fix gate-ledger durability + ban blanket overrides** (one reason pasted across 11 gates defeats the audit trail). Move ledger storage out of the plugin-reinstall blast zone.
4. **Strengthen the weakest link, not the strongest.** task-verifier rubber-stamps; the fresh-context re-audit (kit-hardening SG-04 recheck-verifier, pinned to re-execution) is precisely the right fix. The live-environment blind spot (4 post-"COMPLETE" launchd bugs, stale-premise handoff) is what SG-07 deployable-done + UAT addresses.
5. **Benchmark the handoff layer on the kit-hardening run** (first real orchestrate.sh exercise): per-sub-goal `claude -p` sessions give clean per-unit token/turn/outcome data; compare DETERMINISTIC_HANDOFF on/off if feasible.
6. **Keep dispatching fresh subagents; stop worrying about their cost.** Watch instead for cache-read blowup in long sessions and for uncached router models.

## Honest limits of this audit

Still judge-by-LLM over records, not a controlled experiment: mitigated by three independent fresh-context miners, raw-data-only sourcing, and citation requirements, but the paired-task A/B (same task, one variable flipped) remains the only way to measure the handoff and framework layers causally. The retros themselves are unusually candid (misses recorded alongside catches), which raises confidence in the record base.

---

# Appendix: full miner reports (verbatim)

## Miner A: token economics (13 sessions, raw JSONL)

Schema notes (verified): assistant messages span multiple JSONL lines (one per content block) sharing message.id + identical usage; numbers deduped by message.id. isSidechain:true never appears in main session files in this harness version; subagent transcripts live at <session-dir>/subagents/agent-*.jsonl (+meta.json). System-reminders persist as type:"attachment" lines, not inline. Subagent dispatch tool is named Agent.

Per-session usage (main thread | sidechain):

| session | API calls | out tok | cache_read | cache_creation | uncached in | SC out | SC cache_read | SC cache_cr | SC uncached | n disp |
|---|---|---|---|---|---|---|---|---|---|---|
| 705351fe | 148 | 130,902 | 33.26M | 924,655 | 67,268 | 614 | 4.03M | 192,977 | 1,802 | 3 |
| 84545463 | 121 | 117,834 | 25.59M | 730,404 | 77,048 | 0 | 0 | 0 | 0 | 0 |
| 1e3e2a16 | 98 | 115,822 | 17.12M | 461,557 | 58,822 | 0 | 0 | 0 | 0 | 0 |
| 71ca5bc7 | 188 | 251,340 | 51.80M | 1.88M | 72,867 | 0 | 0 | 0 | 0 | 0 |
| 09ad3cdf | 219 | 368,404 | 68.62M | 2.14M | 80,982 | 0 | 0 | 0 | 0 | 0 |
| 127c12b7 | 440 | 479,778 | 191.34M | 4.81M | 111,495 | 1,614 | 5.22M | 525,241 | 90,094 | 8 |
| bbf59df2 | 135 | 171,405 | 30.33M | 961,969 | 63,638 | 11 | 0.12M | 27,399 | 42 | 1 |
| 568ac26e | 606 | 1,018,772 | 238.31M | 4.92M | 213,606 | 25,983 | 23.87M | 1.59M | 95,600 | 14 |
| b77834a8 | 72 | 74,910 | 13.77M | 480,297 | 55,240 | 564 | 1.44M | 56,402 | 306 | 1 |
| b9e3f131 | 137 | 148,139 | 31.80M | 1.23M | 57,996 | 108 | 0.55M | 93,822 | 17 | 2 |
| a427462c | 117 | 139,355 | 23.30M | 736,445 | 70,075 | 3,493 | 0.11M | 44,057 | 6 | 1 |
| e36301f6 | 193 | 63,965 | 20.95M | 0 | 601,089 | 0 | 0 | 0 | 0 | 0 |
| 53b43cd0 (dwarves-kit) | 131 | 97,400 | 25.89M | 1.42M | 60,908 | 0 | 0 | 0 | 0 | 0 |
| TOTAL | 2,605 | 3.18M | 772.1M | 20.7M | 1.59M | 32,387 | 35.3M | 2.53M | 187,867 | 30 |

Sidechain share of grand totals: output 1.0%, cache_read 4.4%, cache_creation 10.9%, uncached input 10.6%. Heaviest sidechain session (568ac26e): 24% of its cache_creation and 31% of its uncached input went to subagents.

Subagent economics (30 dispatches): typical dispatch (median) 16 API calls, 81,876 fresh tok (uncached+cache_creation), 993,836 cache_read, 399 output. Main thread per API call (median): 7,597 fresh, 224,663 cache_read, 1,090 output; ~8.9 API calls per human turn -> ~68k fresh tok per human turn. One dispatch ~= 10.8x one main-thread API call ~= 1.2x one full main-thread human turn in fresh input, plus ~1M extra cache reads. Worked example (568ac26e, security-auditor): 50 calls, 229,177 fresh, 5.15M cache_read, 6,129 out; host main thread averaged 8,479 fresh + 393k cache_read per call. First-call fresh input: Explore 12-21k, security-auditor 26-44k, general-purpose ~85k (vs ~7.6k main incremental call). The "context-inheriting subagents cost 3x" claim not testable: zero fork-type dispatches in sample; all 30 fresh-context (Explore 12, security-auditor 15, general-purpose 4, reviewer 5, doc-verifier 1). Total sidechain overhead 4-11% of session tokens even in dispatch-heavy sessions.

Hook/system-reminder overhead: inline system-reminders near zero (3 occurrences <100 bytes total); attachments instead. Top types: skill_listing 1,494KB/61 (24.5KB avg), hook_success 1,447KB/1,182 (1.2KB avg), deferred_tools_delta 371KB/30, output_style 255KB/1,863, edited_text_file 233KB/36, hook_additional_context 121KB/70. Per session ~26k-305k est. tokens of attachments = 3-11% of main-thread fresh input (median ~6%), ~2,200-5,200 est. tokens per human turn. Upper bound (harness may cache some types).

Skill fires: 18 fires, 17 with follow-through (>=2 subsequent consistent tool calls): secret-guard-fix x3, repo-layout-tidy x2, work-intake, repo-sweep, extract-workflow, superpowers:writing-skills, plan-for-mega-goal, kit:verify, kit:ship, kit:debug, kit:retro, wrap-session, prompt-improver, content-spec x1 each; only opencode-usage fired with no follow-through (~6% ignored).

Striking: (1) cache-read dominance 772M vs 1.59M uncached (485:1); (2) GLM-5.2 router session: cache_creation 0, uncached 601k (9x any Claude session); (3) giant single messages (1,146KB tool_result line; 23,554-token single assistant output); (4) re-read churn (secret-guard.sh read 21x, SKILL.md 11x, one research file 7x); no consecutive-identical retry storms (max 2); (5) error rate 5-31 is_error tool_results per session (worst ~5%).

## Miner B: catch-vs-ceremony (mega-goal records, retros, ledgers)

CATCHES (cited): (1) CHANGELOG.md:260 SPEC-028: task-verifier caught a DEC-005 guard drift, integration-checker a second, /user:review a third, three layers, three distinct catches, one cycle. (2) RETRO-2026-05-21: /review caught a CRITICAL `rm -rf node_modules/../..` traversal escape that per-task self-verification reported green on. (3) LAB_LOG:3152 SPEC-076: TASK-004 inverted on-demand/link precedence (fixed f7e6289); integration-checker found runbook sentinel mismatch (aligned acb6b81). (4) spec-validate pre-build criticals: SPEC-105 3 criticals folded in; SPEC-109 NEEDS REVISION -> fixed; placement-ui-design retro: "caught a real defect in my work on every spec, five times total". (5) homelab-mesh-ops FINAL-REVIEW: 12 applied fixes (fail-closed MULTIFILTER desync, nvram allowlist, null-byte guard...), tests 31->37. (6) token-optim-v3 RETRO: round 2 caught a regression round 1's own fixes introduced ("Self-review would never have found it"). (7) same RETRO: fact-check gate killed a phantom HIGH (stale local master ref; gh pr diff proved it). (8) token-optim-v2: negative control caught a real verdict.py bug (dropped baseline control, false PASS). (9) test-meta.sh fails closed, forced completeness twice ("Structure did the remembering"). (10) ship-gate.log: 7 BLOCKED pushes 2026-07-01 (2 ship-gate, 5 proof-gate); safety-gate.log: 5 blocked destructive commands. (11) v2 SG-05/SG-09 ablations: "the split NEVER won -> DROP", the process kills its own work on evidence.

Honest MISSES (on record): a "replace" task that left both copies passed BOTH task-verifier and integration-checker; /ship trusted a stale narrow REVIEW.md; operator wrote "Status: VALIDATED" without running reviewers on early cycles; red-CI merge sat on master ~50min (nothing requires green checks to merge); homelab-mesh-ops shipped "COMPLETE" then live deploy surfaced 4 launchd bugs unit tests could not see (fix PRs #539-542); safety hook blocks `git reset --hard` but not `git checkout <file>` (silently destroyed uncommitted work).

CEREMONY: gate run-ledger (1 surviving record, 11 gates blanket-overridden with one pasted reason; pre-July ledger wiped by 2026-07-01 plugin reinstall); proof-of-done consumption thin (48 files, some 136K; mechanical filename check + 1 human citation; no post-merge re-reads); FEEDBACK.md partially dead (cross-repo worktree friction logged 3x/9 days, zero fix; vps-mon dry-run-harness proposal unbuilt). Counter-evidence: NOTES Proposed-additions get read (one became kit-hardening; icy deferred MAJOR became icy-ops-enhancements goals 05/06).

HANDOFF verdict: dead-letter, never exercised. Mandate real (subgoal-template.md:50-51; orchestrate.sh:231-235 injects them). Zero commits ever touched HANDOFF*/DECISIONS* in ops-toolkit; zero files exist; no .orchestrate/ state dir anywhere. Contract entered the template 2026-06-29; v3 ran interactively; kit-hardening not yet run. orchestrate.sh + two-tier handoff + handoff_gen.py (default-off) are built-and-tested with zero production runs. Nuance: ad-hoc handoffs DO get consumed and one stale one caused damage (vps-mon SG-02 built on stale writebook premise, rework PR #452).

Rework/blocker stats: token-optim-v2 12/12 merged, 2 CI-red fix cycles, 2 stacked conflicts, false-PASS fix; homelab-mesh-ops 9/10 merged (1 dropped by Han), 12 review fixes, 4 post-COMPLETE live-deploy fix PRs; vps-mon-hardening 3/3 + stale-premise rework PR #452; icy-operations 5/6 (1 blocked cross-repo cwd), ~9 inline fixes; token-optim-v3 7/7, round-1 fixes regressed caught round 2.

## Miner C: overhead per shipped change (10 merged PRs per repo)

| Repo | Median % process lines/PR | Range | Aggregate lines | Aggregate files |
|---|---|---|---|---|
| ops-toolkit (#608-619) | 83.8% | 31.7-100% | 1,227/2,421 = 50.7% | 40/72 = 55.6% |
| dwarves-kit (#87-98) | 34.9% | 0-75.4% | 3,719/6,613 = 56.2% (26.6% excl. one 2,671-line report) | 19/65 = 29.2% |

Pure-ceremony PRs (>80% process files): ops-toolkit 5/10 (e.g. #609 archive megagoal 100%, #610 retro 100%, #619/#616/#613 row-shuffling 100%); dwarves-kit 0/10. Process lines >= work lines: ops-toolkit 7/10; dwarves-kit 2/10. Worst ratio: dwarves-kit #95, 2,872 process lines for ~85 work lines (~32:1).

Consumption per artifact: BACKLOG READ-LATER (board/board-all/backlog.sh/kit:start/triage.py); Specs READ-LATER (spec-index.sh, execute/next implement FROM spec, task-verifier verifies against ACs); proof-of-done READ-ONCE by ship-gate (forcing function); LAB_LOG WRITE-MOSTLY (session-closer hook greps diff presence only, line 91; ~8 generic citations; only reader is human-invoked narrate-log); impl-notes WRITE-ONLY (mandated by execute.md:141/next.md:56; no parser, no retro read, one code-comment cross-ref).

Findings: process begets process (5/10 PRs exist only to do bookkeeping about other PRs); ceremony floor ~50-115 lines constant so small changes drown (PR #618: 88 process lines for 64 work lines); dwarves-kit leaner because bookkeeping rides inside feature PRs; consumption bimodal; proof-of-done's value is the forcing function, not the artifact.
