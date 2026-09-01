Mega-goal kit-adopt-enforce: make the dwarves-kit full-flow orchestration self-install and self-enforce per-repo. Roadmap + sub-goals: ~/workspace/<owner>/ops-toolkit/_meta/megagoals/kit-adopt-enforce/. Every turn, read ROADMAP.md + NOTES.md and the goals/NN-*.md for the sub-goal you are on.

Three sub-goals, one destination: adopting a repo is one command, and a full-lane change cannot ship review-less because lane + loop-type classification drives the gates. Build the dwarves-kit sub-goals (01, 02) THROUGH the kit's own full lane (the dogfood): /kit:start, /kit:assign lane=full, /kit:think, /kit:spec, /kit:spec-validate, /kit:execute, /kit:review-team, /kit:docs, /kit:ship, with `lib/gate-ledger.sh` recording each gate. Reuse the existing classifiers (lib/{lane-classify,task-type-classify,proof-gate}.sh); do NOT rebuild them or change the lane / proof-class taxonomy.

Where each sub-goal lives (use absolute paths; this loop is cross-repo):
- 01, 02 -> ~/workspace/<owner>/dwarves-kit. SHARED repo: branch in a worktree, PR, CI green, NEVER merge, never auto-merge. These need Han's nod.
- 03 -> ~/workspace/<owner>/ops-toolkit.

Hard rules (commands, not suggestions):
- One PR per sub-goal. A sub-goal that is only a local diff is unstarted. The moment `gh pr create` returns a URL, write `PR #N` on that sub-goal's ROADMAP.md row. Flip `[ ]`->`[x]` ONLY when its goals/NN Done is verified by its own close-the-loop commands AND the PR is open + CI green (`gh pr checks <N>`) + not CHANGES_REQUESTED. A checked box without a passing PR # is invalid.
- gh, no stack tool: sequential. 02 depends on 01; 03 depends on 01+02. Open a dependent sub-goal's PR only after its prerequisite PRs are MERGED to main by Han (you do not merge). Rebase the dependent branch on main first. While waiting on a merge, mark blocked and stop (see stop rule).
- Do NOT merge any PR. Do NOT edit a sub-goal's Outcome or `Done =` (append to its `## Notes` for deviations). Discovered sub-goals -> NOTES.md `## Proposed additions`, never inline.
- NOTES.md: `## Active blockers` updated IN PLACE (fingerprint: command · failure · prerequisite · last verified); `## Event log` + `## Proposed additions` append-only. Log skill/tooling/codebase friction to FEEDBACK.md as you hit it.
- Retry a blocked sub-goal only when its prerequisite changed since `last verified`.
- Three stop conditions: (a) all three rows `[x] — PR #N` and audited; (b) every remaining sub-goal blocked on an unchanged prerequisite (you are waiting on a human merge); (c) budget exhausted. Anything else: keep moving.
- Before claiming mega-goal complete, AUDIT: `grep -oE 'PR #[0-9]+' ROADMAP.md`, then `gh pr view <N> --json state,reviewDecision,statusCheckRollup` for each. Any not open+green+non-CHANGES_REQUESTED: uncheck and keep working.
- On the FIRST blocked-stop, append a final summary block to NOTES.md `## Event log`. On later blocked-stops emit ONLY `🛑 LOOP BLOCKED — STOP /goal MANUALLY` (no re-audit, no repeat summary).
- ops-toolkit close-out: before marking the mega-goal complete, draft a one-paragraph `_meta/LAB_LOG.md` entry (slug, 3 sub-goals, PR range, key lessons) as the newest entry on sub-goal 03's branch so it rides into PR #03 (SPEC-005). Then mark complete.

Turn-1 pre-flight: `gh auth status` works; read the three goals/ files; for each sub-goal check whether its Done is already true (if so, mark it and move on). Then start at 01.
