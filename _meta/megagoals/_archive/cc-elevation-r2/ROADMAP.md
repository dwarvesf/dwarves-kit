# Mega-goal: cc-elevation-r2

**Destination:** The remaining high-value Claude Code capabilities go live, nothing left inert: my phone gets pinged when a loop needs me; JIT skill hints fire on my real intents; prior notes auto-surface on recall prompts; fresh worktrees self-provision; recurring fan-outs are one named command; a weekly job sweeps my repos + proposes cross-session learnings; the session-close LAB_LOG entry drafts itself; and I can mint a focused subagent from a description.
**Quality bar:** Minimum-infra first (native/config before a new daemon); every hook earns its latency; nothing private leaves the Air (local fastembed; reasoning via Claude Haiku, never mini.ollama); propose-don't-dispose for anything touching durable homes (ledger / LAB_LOG / board); every new tool ships a proof-of-done.
**Stacking tool:** gh (all 9 independent: branch each off main, open in parallel; stagger MANIFEST/BACKLOG insert slots to merge clean)
**Started:** 2026-06-15

## Sub-goals

- [x] ~~01-cc-notify, phone push on /goal loop-finish + input-needed~~ SUPERSEDED by cc-elevation-r3 SG-05 (channel decision resolved 2026-06-15 = vps-mon ingest + public /status, not a phone-push channel). Closed via r3 SG-05.
- [x] 02-skills-map-seed, seed cc-context skills-map.json with real keyword->skill pairs so JIT hints fire on my phrasings, PR #275
- [x] 03-prose-rag-autoinject, activate prose-rag inject gated to recall/research prompts (opt-in), silent on operational prompts, PR #277
- [x] 04-worktree-autoprovision, WorktreeCreate hook symlinks env + runs install on a fresh worktree, no-ops cleanly otherwise, PR #278
- [x] 05-saved-workflows, 2-3 named Workflows (review-branch, research-sweep, cross-repo-sweep) invocable by name, PR #280
- [x] 06-scheduled-intel, weekly launchd job: cc-observe + repo-sweep digest + cross-session synthesis + repeat-sequence detection, PR #282
- [x] 07-docs, Round-2 section in the research note + Monitor/LSP usage cheatsheet, PR #284
- [x] 08-meta-agent, generate a valid scoped subagent spec from a description, PR #287
- [x] 09-auto-lab-log, cc-harvest SessionEnd drafts a staged hygiene-compliant LAB_LOG entry (never auto-writes LAB_LOG.md), PR #290

## Dependencies

All 9 are independent: each adds a new tool or extends an already-merged one (cc-observe #261, prose-rag #265, cc-harvest #267, repo-sweep #268/#269, cc-context #274). Open in parallel off `main`. Stagger MANIFEST.md / BACKLOG.md insert slots per sub-goal (distinct rows) so parallel PRs merge without conflict; edit only your own line in ROADMAP.md. The cc-elevation run proved this pattern.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read pr; do
      gh pr view "${pr#PR #}" --json state,reviewDecision,statusCheckRollup
    done

## Source

Analysis: `research/2026-06-14-claude-code-events-tools-elevation.md` (round-1 + the round-2 frontier this session). Borrow rows: `_meta/BACKLOG.md` (reconcile ID-081..084; add ID-085+ for new items).
