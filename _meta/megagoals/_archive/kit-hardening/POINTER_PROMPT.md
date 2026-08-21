Objective: harden the dwarves-kit autonomous SDD loop per ADR-0028 (team-blessed 2026-07-01) + ADR-0029, so a full run stops only at ONE final human review. 8 sub-goals live in `~/workspace/<owner>/ops-toolkit/_meta/megagoals/kit-hardening/`.

SETUP (turn 1). Run from a session whose cwd IS `~/workspace/<owner>/dwarves-kit` (the `/kit:*` commands + `lib/` bind to cwd; the roadmap lives cross-repo in ops-toolkit). Pre-flight `which gh` (required; if missing, stop). Read the ROADMAP.md, NOTES.md, and every `goals/NN-*.md` under the kit-hardening dir above. Create the integration branch `mega/kit-hardening` off `master` if absent. dwarves-kit is kit-adopted: read AGENTS.md + WORKFLOW.md FIRST (the operate-contract, the authority on how each phase runs).

SOURCE OF TRUTH. ROADMAP.md = what-is-done + which PRs belong. Each `goals/NN-*.md` holds a sub-goal's immutable contract (Done=, verification, deps, Model/Effort). ADR-0028 + ADR-0029 in `dwarves-kit/docs/decisions/` are the intent.

MERGE POSTURE (integration-branch + gated-final). Every sub-goal PR targets `mega/kit-hardening`, NEVER `master`. Once a sub-goal's ship-gate passes (Done= verified + gate-ledger recorded + `gh pr checks` green + proof-of-done committed with CAPTURED evidence, never just "passes"), auto-merge its PR INTO `mega/kit-hardening`. When ALL 8 boxes are `[x]`, run the TIER-4 close gate, then open the ONE final PR `mega/kit-hardening -> master` and STOP for Han. NEVER merge the final PR (gated-final).

PER SUB-GOAL (respect deps: 03+04 need 01+02; 05 needs 03+04; 08 needs 07; 01/02/06/07 independent):
- `bash lib/lane-classify.sh classify "<the sub-goal>"`, run that lane. `/spec` then `/spec-validate` before code.
- Build with `/kit:execute` (per-sub-goal V-model fires: task-verifier + integration). Converge verify->fix->re-verify to the sub-goal's named Proof, bounded ~a few attempts. Never check a box on a failing proof.
- Record each phase gate via `bash lib/gate-ledger.sh record` so the ship-gate passes. Commit the proof-of-done run-table.
- Branch `feat/kit-harden-NN-<slug>` off `mega/kit-hardening`, PR base `mega/kit-hardening`. Set the ROADMAP line to `PR #N` when opened; to `[x] ... merged <sha>` when merged into the integration branch.

TIER-4 CLOSE (on the assembled `mega/kit-hardening`, after all 8 merge): integration-verifier against the objective (do the sub-goals wire together?), `/review-team` + the deep `security-reviewer` lens, over-test the whole. Only open the final `-> master` PR when clean.

HARD RULES. One PR per sub-goal, into the integration branch. A checked box is `[x] ... PR #N ... merged <sha>` or it is not checked. "CI green" = `gh pr checks <pr>` on the OPEN PR, not local tests. Never rewrite a sub-goal's Done=/Outcome (append `## Notes` only). No new sub-goals mid-loop (-> NOTES `## Proposed additions`). Retry a blocked sub-goal only when its prerequisite changed since last-verified. On any stop, append a final summary to NOTES `## Event log` on the FIRST stop only; subsequent stops emit a one-line `LOOP BLOCKED , STOP /goal MANUALLY` banner, no re-audit. Before claiming success, audit every ROADMAP PR # via `gh pr view <n> --repo dwarvesf/dwarves-kit --json state,reviewDecision,statusCheckRollup`; unmark any box whose PR fails.

STOP CONDITIONS. Success = all 8 merged into `mega/kit-hardening` AND the final `-> master` PR opened + HELD for Han. Also stop: a genuine blocker whose prerequisite is unchanged, or token budget exhausted. Anything else: keep moving.

CLOSE-OUT (ops-toolkit). Before marking the mega-goal complete, draft a single-paragraph `_meta/LAB_LOG.md` entry (slug, 8 sub-goals, PR range, key lessons) and append it as the newest entry on the LAST sub-goal's branch so it rides into the final PR (SPEC-005). Then mark complete.
