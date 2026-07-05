Objective: human gates get a surface, reviews get a memory: plannotator `--gate --json` trialed as the gate surface (decision + feedback into the ledger), review lenses remember rejected findings (per-repo ledger + `findings=/rejected=` emits), the observatory prices lens false-positives (`review-yield`), and the stale-ADR inversion + deny triage-first contract + measurement principles land. Scaffold: _meta/megagoals/gate-review-absorptions/ (ROADMAP.md = source of truth; goals/01..06 = the contracts; NOTES.md per its section rules). You own ONLY this scaffold.

RUN CONTRACT: ops-toolkit _meta/megagoals/OPERATE.md is BINDING (checkpoint discipline, progress strips, visible close/RUN_REPORT).

LAUNCH GUARD (verify first): both sibling megas (harness-observatory, kit-absorptions) must show all ROADMAP boxes flipped + PRs merged; either live -> STOP and report (file overlap).

RUN MODE: subagent-delegate. You are the THIN CONDUCTOR: never run a sub-goal inline. CROSS-REPO RULE (binding): 01/02 target dwarves-kit while this session sits in ops-toolkit; Agent isolation:worktree would cut from the WRONG repo, so hand-make their worktrees (git -C <repo> worktree add .claude/worktrees/<name> -b <branch> <base>) and pin the worker's cwd. 05/03/04 use native worktrees. Two stacks as parallel lanes: dwarves-kit 01 -> 02 -> 06 and ops-toolkit 05 -> 03 -> 04; one worker per lane at a time (stacked PRs; stack heads base their repo's default branch). 04 also waits for 02 MERGED (grammar), verify `gh pr view`.

TIER 0: both repos are kit-adopted: workers read AGENTS.md + WORKFLOW.md first, lane-classify per sub-goal, record every phase via lib/gate-ledger.sh (ship-gate = the Done check); 05 is docs-only tiny lane, record it.

SETUP (once): reserve a dwarves-kit SPEC block (spec-next reserve) for 01/02 into HANDOFF.md; workers NEVER self-pick numbers.

TIER 1: SKIP grill/think/design, framing is done (research/2026-07-04-pxpipe-plannotator-improve-absorption.md + ROADMAP ## Assumptions). Do not re-ask.

TIER 3 per sub-goal: build, converge to the NAMED Proof. OVER-TEST 02/03/04: test-plan, risk-matched modes, COVERAGE-DELTA row. Load-bearing NCs are absolute: 02 novel-finding-still-fires (memory never mutes a fresh defect), 03 malformed-JSON/missing-binary fail-open with NO ledger write (never a fabricated decision), 04 honest-zero (no data -> zero rows, never a fabricated rate). 06 is observability-only (advisor emit; NCs honest-zero + emit-failure-never-blocks). NO gate-REQUIREMENT changes anywhere; the wrapper is an OPTIONAL surface. 03 installs plannotator verify-then-run (pinned + checksum/attestation, NEVER curl|bash), no secrets to it.

MERGE: auto-bottom-up, gated-final. NEVER merge 03 or the final PR (gate banner, hold for Han; 03's held review IS the live trial). Retarget child PRs BEFORE deleting a merged parent branch. All auto-merge gates apply incl. captured evidence; never red CI or CHANGES_REQUESTED.

CONVERGENCE GATE close, on the assembled stacks: integration-check against the objective, then the DEMO RUN: a real human-gate review through pl-gate with its ledger line, `review-yield` on the golden fixture + real ledgers, a review dispatch showing the stale-ADR lens + rejected-findings check live. Write RUN_REPORT.md into the mega dir and render it in chat as the final message. Before complete: one-line _meta/LAB_LOG.md entry on the last sub-goal's branch (SPEC-005) + flip cockpit rows ID-262/263/264 + ID-267 with PR refs.

STOPS (genuine): launch guard failing, gate 03 + held final PR (banner: NEEDS APPROVAL, STOP /goal MANUALLY), 04's dependency unchanged after both lanes otherwise done, all-blocked-unchanged, token budget. Blocker fingerprints live in NOTES.md ## Active blockers; ## Event log gets the final summary once. One PR per sub-goal; PR # on the ROADMAP line the moment it exists; a checked box is `- [x] ... PR #N` or it is not checked.
