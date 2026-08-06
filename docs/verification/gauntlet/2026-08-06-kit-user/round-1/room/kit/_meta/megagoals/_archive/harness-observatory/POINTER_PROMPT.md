Objective: close the observatory half of the harness benchmark loop. Ship gate-yield, defect-correlation, deviation-rate, the numeric-only sessions/safety planes, the memory-hygiene lens, and the ledger digest scorecard, all running on REAL data. Scaffold: _meta/megagoals/harness-observatory/ (ROADMAP.md is the source of truth; goals/01..06 are the contracts; NOTES.md per its section rules). Sibling run kit-absorptions covers the dotfiles/kit lanes and may be running in parallel; you own ONLY this scaffold.

RUN CONTRACT: ops-toolkit _meta/megagoals/OPERATE.md is BINDING (checkpoint discipline, progress strips, visible close/RUN_REPORT).

RUN MODE: subagent-delegate. You are the THIN CONDUCTOR: never run a sub-goal inline. All six sub-goals live in THIS repo (ops-toolkit): dispatch each as ONE background subagent (Agent tool, isolation: worktree, model from its Model: line) whose prompt is the sub-goal file's contract. The chain is strictly serial (01 -> 02 -> 03 -> 04 -> 05 -> 06, every sub-goal touches tools/ledger-observatory/**): one worker at a time, stacked PRs, each PR based on its parent branch (01 bases main).

TIER 0: ops-toolkit is kit-adopted: workers read AGENTS.md + WORKFLOW.md first, lane-classify per sub-goal, record every phase via lib/gate-ledger.sh (the ship-gate is the Done check).

SETUP (once, before dispatching 01): reserve a SPEC-number block (spec-next reserve) and write the reserved numbers into HANDOFF.md; workers NEVER self-pick numbers (wavefront race).

TIER 1: SKIP grill/think/design. Framing is done: the design docs are cited in each goal file; ROADMAP ## Assumptions holds the answered questions. Do not re-ask them.

TIER 3 per sub-goal: /spec + spec-validate before code (each goal file's Design: line says bearing|obvious). Build, then converge to the NAMED Proof. OVER-TEST every sub-goal (all six are marked): test-plan, risk-matched test modes, record the COVERAGE-DELTA row in the proof-of-done. The negative controls named in each goal file are LOAD-BEARING and absolute: the privacy NC in 05 (a fixture fake-secret string provably absent from the materialized db) and the never-delete NC in 06 (byte-identical memory stores after the sweep) are hard requirements, not suggestions. A benchmark that lies is worse than none.

MERGE: auto-bottom-up, gated-final. NEVER merge 05 or the final PR (emit the gate banner and hold for Han). Retarget the child PR to the new base BEFORE deleting a merged parent branch. All five auto-merge gates (incl. captured evidence, real stdout, never a bare GREEN) must hold; never merge red CI or CHANGES_REQUESTED.

TIER 4 close, on the assembled stack: integration-check against the objective, then the PAYOFF RUN on real ledgers: ledger rebuild; gate-yield; defect-correlation; deviation-rate; digest. Render the FIRST REAL BENCHMARK SCORECARD + write RUN_REPORT.md (ASCII gantt, gate matrix, worker minutes by model, totals) into the mega-goal dir and render it in chat as the final message. Before marking complete: draft the one-paragraph _meta/LAB_LOG.md entry on the last sub-goal's branch (SPEC-005) and flip cockpit rows ID-245, ID-248, ID-251, ID-255 with PR refs.

STOPS (genuine): the 05 gate + the held final PR (banner: NEEDS APPROVAL, STOP /goal MANUALLY), blocked-with-unchanged-prerequisite, token budget. Blockers carry fingerprints in NOTES.md ## Active blockers; ## Event log gets the final summary once. One PR per sub-goal; PR # on the ROADMAP line the moment it exists; a checked box is `- [x] ... PR #N` or it is not checked.
