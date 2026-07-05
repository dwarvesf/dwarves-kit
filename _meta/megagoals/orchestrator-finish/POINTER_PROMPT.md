Objective: finish hardening the dwarves-kit orchestrator via the 6 orphaned orchestrate-hardening sub-goals in _meta/megagoals/orchestrator-finish/ (dwarves-kit BACKLOG ID-091,093,094,095,096,097,098,099). Destination: token accounting complete on every path, gate coverage auditable, no unbounded secret-bearing stream, TIER-4 close split into 3 independent verifiers. Boring and bulletproof, nobody debugging an overnight run has to guess whether the numbers are real.

REPO: dwarves-kit, kit-adopted. Run this loop FROM the dwarves-kit repo root (cwd) so sub-goals use the SDD lane + /kit:* natively and worktrees cut from the right repo.

RUN MODE: subagent-delegate. You are the THIN CONDUCTOR: never build+verify a sub-goal inline. Compute the ready-set from each goal file's `Depends on:`; dispatch each ready sub-goal as ONE background subagent (Agent tool, isolation: worktree, model from its `Model:` line) whose prompt is the goal file's full contract. On completion: verify the ROADMAP box on disk, absorb only the terse report, auto-bottom-up merge, dispatch the next wave. Render a per-worker PROGRESS STRIP at each check-in (gates recorded vs the lane plan, from the run-ledger + `gate-ledger.sh plan <lane>`, never the transcript).

RUN CONTRACT: ~/.claude/skills/plan-for-mega-goal/references/OPERATE.md is BINDING (run-mode, progress strips, visible close + RUN_REPORT).

SCAFFOLD: _meta/megagoals/orchestrator-finish/, ROADMAP.md is the source of truth for what's done + which PRs belong; goals/01..06 are the immutable contracts; NOTES.md holds Active blockers (in place) / Proposed additions (append) / Event log (append).

STACK: 01-gate-vocab is independent (edits hooks/ship-gate.sh + gate-ledger.sh), base main. 02→03→04→05→06 are stacked (each PR base = the prior sub-goal's branch) because they all edit lib/queue/orchestrate.sh, the stack serializes those edits to avoid conflicts, it is NOT a logical dependency. So wave 1 = {01, 02}; 03 after 02 merges, 04 after 03, etc. 01 runs in parallel with the orchestrate.sh chain.

MERGE: auto-bottom-up + gated-final. Merge each `auto` sub-goal's PR once ALL five auto-merge gates hold (its Done= verified by its own close-the-loop; `gh pr checks` all-green on the OPEN PR; reviewDecision not CHANGES_REQUESTED; a proof-of-done committed WITH captured evidence, not the word "passes"; tagged `auto`), do the retarget-child-before-delete dance yourself. All 6 are `auto`; STOP only at the final PR for Han's single click. NEVER merge a red-CI or CHANGES_REQUESTED PR.

KIT-ADOPTED lane: each sub-goal reads AGENTS.md + WORKFLOW.md first, classifies its lane with `bash lib/lane-classify.sh classify "<task>"`, builds+verifies to its Done=, and records each phase via `bash lib/gate-ledger.sh record <rid> <phase> ran "<evidence>"` so the ship-gate passes. Drive the lane via lib/ + gate-ledger (not /kit:* unless cwd is dwarves-kit).

HARD RULES: one PR per sub-goal; record PR # on the ROADMAP line the moment it opens; a checked box is `[x] — PR #N` or it is unchecked; "CI green" = the open PR's checks, not local tests; do not rewrite any Done= mid-loop; no new sub-goals mid-loop (discovered ones → NOTES ## Proposed additions); ROADMAP.md is the source of truth. Before claiming success, audit every `PR #N` in ROADMAP via `gh pr view`.

SUCCESS = all 6 boxes checked-with-PR and merged bottom-up except the final PR held for Han (gated-final). Before marking complete: write RUN_REPORT.md into the mega dir (ASCII timeline + worker-minutes-by-model + gate-coverage matrix + totals) and render the timeline + totals in chat as the closing message; flip each shipped item's row on dwarves-kit `_meta/BACKLOG.md` to shipped.
