You are running the `token-optim-v3` mega-goal. Source of truth on disk: `~/workspace/<owner>/ops-toolkit/_meta/megagoals/token-optim-v3/`. Read `ROADMAP.md` every turn and the relevant `goals/NN-*.md` before working a sub-goal. Do not rederive scope.

This wave complements token-optim-v2 by adopting pi-vcc (deterministic no-LLM compaction + recall) + a meta-agent. Done: SG-01 (#598 merged), SG-03 (#599 merged), SG-02 (#90 open+held). Remaining: SG-04, SG-05, SG-06, SG-07. v2 SG-09 LANDED (#601): SG-06 unblocked; SG-07's SG-09 dep cleared (still needs SG-01..04 built).

MERGE POSTURE , open-only / review-at-end (Han 2026-07-01, this OVERRIDES any per-gate-stop default): build a runnable sub-goal, capture its proof, OPEN its PR, record the PR # on its ROADMAP line, then CONTINUE to the next runnable sub-goal. The loop MERGES NOTHING and never halts between sub-goals. Han reviews + merges the whole set in one end-review. (Kit human-ship is preserved because the loop never merges; only the per-sub-goal interruption is removed.)

Rules (commands, not suggestions):
- One PR per sub-goal; a local-only diff is an unstarted sub-goal. Flip `- [x] , PR #N` only when the sub-goal's named proof is CAPTURED and its PR is open. Never merge, never auto-merge, no retarget dance (Han merges bottom-up at end-review).
- Proof = CAPTURED evidence (run-table / screenshots / GIF / TEST-REPORT), never a bare "passes". UI/interactive sub-goals owe 2-3 screenshots or a GIF (before/action/after). Converge to the proof before flipping the box. Scrub any committed transcript fixture of secrets/PII.
- "CI green" = the open PR's `gh pr checks <pr>`, never local tests.
- Stacking (`gh`, cross-repo): base each on its repo default + PORT SG-01's technique (no git-stack across repos). SG-04 -> dotfiles `main`; SG-05/06 -> dwarves-kit `master`; SG-07 -> ops-toolkit `main`.
- SG-04 RESOLVED (Han 2026-07-01): an additive `/dcompact` SLASH COMMAND (not a hook; manual opt-in; native /compact untouched), in the DOTFILES repo.
- Kit-adopted repos (dwarves-kit, ops-toolkit): the sub-goal reads AGENTS.md + WORKFLOW.md, classifies via lane-classify, records gates via lib/gate-ledger.sh. `/kit:*` binds to cwd; for a sub-goal in another repo, drive lib/ + gate-ledger directly. Don't author kit specs from the ops-toolkit cwd.
- Don't rewrite a sub-goal's Done=. No new sub-goals mid-loop (log to NOTES.md `## Proposed additions`). ROADMAP.md is the source of truth for done + PR #s.
- Worktree per sub-goal. Cross-repo (dwarves-kit, dotfiles) can't use native EnterWorktree from an ops-toolkit cwd; `git worktree add <repo>/.claude/worktrees/<name>` off the repo default.
- Token hygiene (the wave's subject): push big reads to subagents, read narrow slices, pipe big output to files, keep the lead lean. `/clear` + re-paste this pointer between sub-goals.
- No clarifying questions mid-loop: reversible unknowns decided per the autonomous contract; the rest -> NOTES.md `## Proposed additions`. Sub-goal files already carry the resolved decisions.

Stop conditions:
- SUCCESS = every sub-goal has its proof captured + an OPEN PR held for Han. Then (ops-toolkit SPEC-005) draft a one-paragraph `_meta/LAB_LOG.md` arc entry (slug, sub-goal count, PR range #90..#NN, key lessons) on the LAST sub-goal's branch so it rides into its PR. Emit `🛑 ALL SUB-GOALS OPEN , STOP /goal, HAN END-REVIEW` listing every PR #.
- BLOCKED = a sub-goal blocked on an unchanged prerequisite: log to NOTES.md `## Active blockers` (fingerprint: command · failure · prerequisite · last verified), then SKIP to the next runnable sub-goal (don't stop while others are workable).
- On any stop append a summary to NOTES.md `## Event log`. On repeated all-blocked stops emit ONLY the banner.

Start: next runnable is SG-04 (dotfiles /dcompact), SG-05 (kit meta-agent drafter), SG-06 (kit data-driven routing), SG-07 (ops-toolkit ablation, after SG-04). Open each PR, merge none, continue; stop once all are open + held.
