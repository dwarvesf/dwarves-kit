Objective: make the dwarves-kit harness config-driven AND tidy, via the 13 sub-goals in _meta/megagoals/harness-ops/. Track A (config-layer, 01-08) puts one kit.toml (kit-root default + per-project .kit.toml override) behind one resolver driving modules/ledger/mega, exposes a stable consumer entrypoint, and documents the consumer contract. Track B (docs-restructure, 09-13) resolves the proof/verification split-brain, de-clutters docs/, and slims the 3 giant root files. Destination: the config surface is the single honest place to tune the harness, and a newcomer isn't overwhelmed by the repo.

REPO: dwarves-kit, kit-adopted. Run this loop FROM the dwarves-kit repo root (cwd) so sub-goals use the SDD lane + /kit:* natively and worktrees cut from the right repo.

RUN MODE: subagent-delegate. You are the THIN CONDUCTOR: never build+verify a sub-goal inline. Compute the ready-set from each goal file's `Depends on:`; dispatch each ready sub-goal as ONE background subagent (Agent tool, isolation: worktree, model from its `Model:` line) whose prompt is the goal file's full contract. On completion: verify the ROADMAP box on disk, absorb only the terse report, auto-bottom-up merge, dispatch the next wave. Render a per-worker PROGRESS STRIP at each check-in.

RUN CONTRACT: ~/.claude/skills/plan-for-mega-goal/references/OPERATE.md is BINDING (run-mode, progress strips, visible close + RUN_REPORT).

SCAFFOLD: _meta/megagoals/harness-ops/, ROADMAP.md is the source of truth (what's done + which PRs); goals/01..13 are the immutable contracts; NOTES.md holds blockers/additions/event-log. 01 is already BUILT (resolver, c84cda5 on feat/config-layer), it needs its own PR but not a rebuild.

WAVES / STACK (from the Dependencies section): Track A and Track B are INDEPENDENT parallel streams.
- Track A: after 01, {02, 03, 08} are a parallel wave (depend only on 01, base main). Then 04 (base main, deps 01) → 05 (deps 04) → 06 (deps 05) → 07 (deps 05+06). 04/05/06 chain because they touch install/adopt.
- Track B: 09 (gate, standalone), {10, 11} parallel (independent doc-moves), 12 (standalone, highest-risk), 13 last (deps the tree state of 09/10/11). All base main.
Base each PR on `main` unless a goal file's `PR base:` names a parent.

MERGE: auto-bottom-up + gated-final. Merge each `auto` sub-goal's PR once ALL five auto-merge gates hold (Done= verified; `gh pr checks` all-green on the OPEN PR; not CHANGES_REQUESTED; proof-of-done committed WITH captured evidence; tagged `auto`). STOP at every `gate` sub-goal (09 is `gate`, the per-slug canonical pick needs Han's eyeball) AND at the final PR for Han's click. NEVER merge a red-CI or CHANGES_REQUESTED PR.

KIT-ADOPTED lane (USE THE SUBDIR PATHS, there are no flat lib/*.sh): each sub-goal reads AGENTS.md + WORKFLOW.md first, classifies its lane with `bash lib/classify/lane-classify.sh classify "<task>"`, builds+verifies to its Done=, and records each phase via `bash lib/gate/gate-ledger.sh record <rid> <phase> ran "<evidence>"` (rid from `bash lib/gate/gate-ledger.sh rid`) so the ship-gate passes. Drive the lane via lib/ + gate-ledger directly.

HARD RULES: one PR per sub-goal; record PR # on the ROADMAP line the moment it opens; a checked box is `[x] — PR #N` or unchecked; "CI green" = the open PR's checks, not local tests; do not rewrite any Done= mid-loop; no new sub-goals mid-loop (→ NOTES ## Proposed additions); ROADMAP.md is the source of truth. Before claiming success, audit every `PR #N` in ROADMAP via `gh pr view`.

SUCCESS = all 13 boxes checked-with-PR, merged per policy except 09 (gate) and the final PR held for Han. Before marking complete: write RUN_REPORT.md into the mega dir (ASCII timeline + worker-minutes-by-model + gate-coverage matrix + totals) and render the timeline + totals in chat; flip each shipped Track-A/B item on `_meta/BACKLOG.md` if it has a row.
