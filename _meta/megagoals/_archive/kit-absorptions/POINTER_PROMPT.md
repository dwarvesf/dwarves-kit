Objective: the kit + planning layer absorbs the field-guide/harness-audit designs: grill conditioned on unknown-density with auditable skips, all 29 kit commands ledger-visible, /kit:pitch + lane de-escalation + the remega Consolidate mode exist, run contracts portable. Scaffold: _meta/megagoals/kit-absorptions/ (ROADMAP.md is the source of truth; goals/01..09 are the contracts; NOTES.md per its section rules). Sibling run harness-observatory may run in parallel; you own ONLY this scaffold.

RUN CONTRACT: ops-toolkit _meta/megagoals/OPERATE.md is BINDING (checkpoint discipline, progress strips, visible close/RUN_REPORT).

RUN MODE: subagent-delegate. You are the THIN CONDUCTOR: never run a sub-goal inline. CROSS-REPO RULE (binding): every sub-goal here targets a FOREIGN repo (dotfiles or dwarves-kit) while this session sits in ops-toolkit; Agent isolation:worktree would cut from the WRONG repo. For EVERY dispatch, hand-make the worktree in the target repo (git -C <repo> worktree add .claude/worktrees/<name> -b <branch> <base>) and pin the worker's cwd there. Two stacks run as parallel lanes: dotfiles 01 -> 02 -> 08 and dwarves-kit 03 -> 04 -> 05 -> 06 -> 07 -> 09; one worker per lane at a time (stacked PRs, each based on its parent branch; stack heads base their repo's default branch).

CROSS-MEGA HOLD (reader-first, binding): 04 and 05 do NOT start until harness-observatory sub-goal 01 (the kit_gates reader) has MERGED, verify via gh pr view; until then treat as a blocker fingerprint and work the other lane.

TIER 0: dwarves-kit is kit-adopted: its workers read AGENTS.md + WORKFLOW.md first, lane-classify per sub-goal, record every phase via lib/gate-ledger.sh (ship-gate = the Done check); /kit:* bind to cwd so cross-repo workers drive lanes via lib/ + gate-ledger directly. dotfiles is NOT adopted: proof in the PR body; dotfiles workers edit chezmoi SOURCE then apply, and stage+commit in ONE shell call (the S-64 watcher reverts uncommitted tracked changes).

SETUP (once): reserve a SPEC-number block in dwarves-kit (spec-next reserve) and write it into HANDOFF.md; workers NEVER self-pick numbers.

TIER 1: SKIP grill/think/design, framing is done (design docs cited per goal file; ROADMAP ## Assumptions holds the answers). Do not re-ask.

TIER 3 per sub-goal: /spec + spec-validate before code where the repo is adopted (Design: line says bearing|obvious; 08 runs on Model: opus, planning-dominant). Build, converge to the NAMED Proof. OVER-TEST the marked sub-goals (04, 05, 06): test-plan, risk-matched modes, COVERAGE-DELTA row in the proof. Load-bearing NCs are absolute: 05's red-NC sweep test, 06's never-auto-post + degrades-gracefully, 08's read-only dry-run (archives byte-identical). NO gate-REQUIREMENT changes anywhere in this run.

MERGE: auto-bottom-up, gated-final. NEVER merge 01, 08, or the final PR (gate banner, hold for Han). Retarget child PRs BEFORE deleting a merged parent branch. All five auto-merge gates incl. captured evidence; never merge red CI or CHANGES_REQUESTED.

TIER 4 close, on the assembled stacks: integration-check against the objective, then the DEMO RUN: grill precheck fixtures live, a real /kit:pitch on a shipped rid, the remega dry-run report. Write RUN_REPORT.md (gantt, gate matrix, worker minutes, totals) into the mega-goal dir and render it in chat as the final message. Before marking complete: draft the one-paragraph _meta/LAB_LOG.md entry on the last sub-goal's branch (SPEC-005) and flip cockpit rows ID-246/247/249/250/252/253/254/256/257/259 with PR refs (ID-258 = adopted-as-practice, note it).

STOPS (genuine): gates 01/08 + the held final PR (banner: NEEDS APPROVAL, STOP /goal MANUALLY), the cross-mega hold with sibling unchanged, all-blocked-unchanged, token budget. Blockers carry fingerprints in NOTES.md ## Active blockers; ## Event log gets the final summary once. One PR per sub-goal; PR # on the ROADMAP line the moment it exists; a checked box is `- [x] ... PR #N` or it is not checked.
