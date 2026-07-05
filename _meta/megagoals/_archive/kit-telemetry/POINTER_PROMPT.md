Objective: close the dwarves-kit measurement loop that kit-hardening opened , durable telemetry, the SPEC-073 effectiveness eval run on real data, lane rules audited, usage visible, auto-merge code-guarded. 5 sub-goals live in `~/workspace/tieubao/ops-toolkit/_meta/megagoals/kit-telemetry/`.

SETUP (turn 1). Run from a session whose cwd IS `~/workspace/tieubao/dwarves-kit`. Pre-flight `which gh` (missing = stop). Read ROADMAP.md, NOTES.md, every `goals/NN-*.md` in the kit-telemetry dir. Kit-adopted: read AGENTS.md + WORKFLOW.md FIRST (the operate-contract).

SOURCE OF TRUTH. ROADMAP.md = what-is-done + which PRs belong. Each `goals/NN-*.md` is that sub-goal's immutable contract (Done=, proof, deps, Model/Effort). Board rows kit ID-082/067/083 + ops ID-149/150 are the briefs; the 2026-07-02 process-effectiveness audit is the evidence base , consume it, never re-derive.

MERGE POSTURE (gh stacked + auto-bottom-up + gated-final). Stack per ROADMAP: 01 off `master`; 02 and 03 base 01's branch; 04 bases 03; 05 off `master`. One PR per sub-goal. Once a sub-goal's gates pass (Done= verified + gate-ledger recorded + `gh pr checks` green + proof committed with CAPTURED evidence, never bare "passes"), the loop MERGES that PR itself, walking the stack bottom-up , BEFORE merging-and-deleting a parent's branch, retarget each child PR's base (`gh pr edit <child> --base master`) so GitHub does not auto-close it. EXCEPTION (gated-final): the LAST PR that would complete the mega-goal is opened + HELD for Han, never merged by the loop. NEVER merge a red-CI or CHANGES_REQUESTED PR.

PER SUB-GOAL (deps: 02,03 need 01; 04 needs 01+03; 05 independent):
- `bash lib/lane-classify.sh classify "<sub-goal>"`, run that lane. `/spec` then `/spec-validate` BEFORE code (02: SPEC-073 already IS the spec , re-validate only if drifted).
- Build with `/kit:execute` (per-sub-goal V-model fires: task-verifier + integration + the kit-hardening re-audit lens). Converge verify->fix->re-verify to the sub-goal's named Proof, bounded ~a few attempts; never check a box on a failing proof.
- Over-test substantial sub-goals: `/kit:test-plan` matrix from the spec ACs, test modes matched to the risk surface, the COVERAGE DELTA recorded as a named proof-of-done row (covered + deliberately-uncovered); trivial keeps its Done-line.
- Record each phase via `bash lib/gate-ledger.sh record` , PER-GATE reasons, no blanket entries.
- Branch `feat/kit-telem-NN-<slug>`, PR base per the stack. Kit board rows (ID-082/067/083) flip INSIDE their sub-goal's PR. ROADMAP line -> `PR #N` on open; `[x] ... merged <sha>` on merge.

TIER-4 CLOSE (after all 5 built, before the final PR is handed to Han): on the assembled result run integration-verifier against the objective (do the pieces wire together?), `/kit:review-team` with the deep `security-reviewer` lens, AND the `advisor` agent in BOTH modes (P5 critique + P6 over-suggest , surface its suggestions to NOTES `## Proposed additions`, do not build them). Fix findings, re-verify, only then hold the final PR.

HARD RULES. A checked box is `[x] ... PR #N ... merged <sha>` or unchecked. "CI green" = the OPEN PR's checks, not local tests. Never rewrite a sub-goal's Done=/Outcome (append `## Notes` only). No new sub-goals mid-loop (-> NOTES `## Proposed additions`). Retry blocked work only when its prerequisite changed. First stop appends a final summary to NOTES `## Event log`; later stops emit only a `LOOP BLOCKED , STOP /goal MANUALLY` banner. Before claiming success audit every ROADMAP PR # via `gh pr view <n> --repo dwarvesf/dwarves-kit --json state,reviewDecision,statusCheckRollup`; unmark any box that fails.

STOP CONDITIONS. Success = 01-04 chain + 05 merged per posture, TIER-4 clean, the held final PR open for Han. Also stop: genuine blocker with unchanged prerequisite, or token budget out. Else keep moving.

CLOSE-OUT. Before marking complete: draft a one-paragraph ops-toolkit `_meta/LAB_LOG.md` entry (slug, 5 sub-goals, PR range, lessons) + a NOTES line for the ops-side close (flip ops ID-149/150). Then mark complete.
