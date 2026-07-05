Objective: make the dwarves-kit telemetry produce CLEAN data + close the SPEC-100 merge-guard loop. 5 sub-goals live in `~/workspace/tieubao/ops-toolkit/_meta/megagoals/kit-telem-cleanup/`. They are the five `#kit-telem-followup` dwarves-kit board rows (ID-085/086/087/088/089) from the kit-telemetry wave's eval + reviews.

SETUP (turn 1). Run from a session whose cwd IS `~/workspace/tieubao/dwarves-kit`. Pre-flight `which gh` (missing = stop). Read ROADMAP.md, NOTES.md, every `goals/NN-*.md`. dwarves-kit is kit-adopted: read AGENTS.md + WORKFLOW.md FIRST , they govern how each phase runs.

SOURCE OF TRUTH. ROADMAP.md = what-is-done + which PRs belong. Each `goals/NN-*.md` is that sub-goal's immutable contract (Done=, proof, deps, Model/Effort). The dwarves-kit board rows ID-085..089 are the briefs; the 2026-07-02 effectiveness-eval + lane-rule-audit + SPEC-100 are the evidence base , consume them, never re-derive.

MERGE POSTURE (gh independent-off-master + auto-bottom-up + gated-final). All 5 sub-goals are INDEPENDENT; each branches off `master` (base `master`). One PR per sub-goal. Once a sub-goal's gates pass (Done= verified + gate-ledger recorded + `gh pr checks` green + proof committed with CAPTURED evidence, never bare "passes"), the loop MERGES that PR itself (squash), then the next sub-goal branches off the updated master (so no child-retarget dance is needed). EXCEPTION (gated-final): the LAST PR that completes the mega-goal is opened + HELD for Han, never merged by the loop. NEVER merge a red-CI or CHANGES_REQUESTED PR.

PER SUB-GOAL:
- `bash lib/lane-classify.sh classify "<sub-goal>"`, run that lane. `/spec` then `/spec-validate` BEFORE code. Build with `/kit:execute` (per-sub-goal V-model: task-verifier + integration + the re-audit lens). Cross-repo caveat: if cwd != dwarves-kit, drive the lane via `lib/` + `gate-ledger.sh` directly, NOT `/kit:*` (they bind to cwd).
- Converge verify->fix->re-verify to the sub-goal's named Proof (run-table + negative control), bounded ~a few attempts; never check a box on a failing proof.
- Record each phase via `bash lib/gate-ledger.sh record` , PER-GATE reasons, no blanket entries.
- Branch `feat/kit-clean-NN-<slug>`, base master. The dwarves-kit board row (ID-085..089) flips to shipped INSIDE its sub-goal's PR. ROADMAP line -> `PR #N` on open; `[x] ... merged <sha>` on merge.

TIER-4 CLOSE (after all 5 built, before the final PR is handed to Han): on the assembled result run integration-verifier against the objective (do the pieces wire together , clean data + closed guard?), `/kit:review-team` with the deep `security-reviewer` lens (04 touches merge machinery), AND the `advisor` agent in BOTH modes (P5 critique + P6 over-suggest , surface suggestions to NOTES `## Proposed additions`, do not build them). Fix findings, re-verify, only then hold the final PR.

HARD RULES. A checked box is `[x] ... PR #N ... merged <sha>` or unchecked. "CI green" = the OPEN PR's checks, not local tests. Never rewrite a sub-goal's Done=/Outcome (append `## Notes` only). No new sub-goals mid-loop (-> NOTES `## Proposed additions`; the eval RE-RUN is parked there , do NOT attempt it, needs days of real usage). Retry blocked work only when its prerequisite changed. First stop appends a final summary to NOTES `## Event log`; later stops emit only a `LOOP BLOCKED , STOP /goal MANUALLY` banner. Before claiming success audit every ROADMAP PR # via `gh pr view <n> --repo dwarvesf/dwarves-kit --json state,reviewDecision,statusCheckRollup`; unmark any box that fails.

STOP CONDITIONS. Success = all 5 sub-goals merged per posture (4 auto-merged + the final held open for Han), TIER-4 clean. Also stop: genuine blocker with unchanged prerequisite, or token budget out. Else keep moving.

CLOSE-OUT. Before marking complete: draft a one-paragraph ops-toolkit `_meta/LAB_LOG.md` entry (slug, 5 sub-goals, PR range, lessons) on the LAST sub-goal's branch so it rides into the final PR (SPEC-005). Then mark complete.
