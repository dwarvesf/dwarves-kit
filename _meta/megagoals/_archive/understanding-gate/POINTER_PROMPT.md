Objective: add an UNDERSTANDING axis to the dwarves-kit SDLC (orthogonal to its verification gates) , a design record before build (human gates direction off a diagram) and an explainer + quiz after (human gates understanding), routed through existing learning skills; two firing modes (inline-on-significant default + weekend batch). 6 sub-goals live in `ops-toolkit/_meta/megagoals/understanding-gate/`.

GATE ZERO (decision, not code). ADR-0031 (understanding gate) must be ACCEPTED. Turn 1: check `dwarves-kit/docs/decisions/0031-understanding-gate.md` Status. If NOT Accepted, write `.planning/BLOCKER-adr.md` and STOP , Han blesses decisions; the loop never self-blesses. This mega-goal EXECUTES ADR-0031, it does not re-decide it.

SETUP (turn 1, after gate-zero). cwd IS `~/workspace/<owner>/dwarves-kit`; pre-flight `which gh`. Read ROADMAP.md (`## Assumptions` BINDING; `## Open forks` /spec-resolved), NOTES.md, every `goals/NN-*.md`; kit-adopted: AGENTS.md + WORKFLOW.md FIRST. SG-01 + SG-05 carry dotfiles halves , chezmoi SOURCE -> `chezmoi apply` -> stage+commit in ONE call.

RUN CONTRACT: `ops-toolkit/_meta/megagoals/OPERATE.md` is BINDING , read turn 1; run mode SUBAGENT-DELEGATE: thin conductor; {01,02,03} = wave 1, dispatched IN PARALLEL as background subagents (`isolation: worktree`, `model` from each goal's `Model:`), terse reports only; merge bottom-up, next wave; TIER-4 likewise. Decorated progress strips at wave check-ins; visible close (RUN_REPORT.md + timeline in chat) , formats per OPERATE.md.

SOURCE OF TRUTH. ROADMAP.md = what-is-done + which PRs belong. Each goals/NN file is immutable contract. ADR-0031 + `ops-toolkit/research/2026-07-03-understanding-bottleneck-sdlc.md` are the intent. THE HARD CONSTRAINT across 03/04/05: explainer + quiz are generated from the ACTUAL diff + recorded test results, NEVER the agent's own narrative (else they teach the agent's misconceptions).

MERGE POSTURE per OPERATE.md. Order (docs last): {01, 02, 03} off `master`; 04 bases 03; 05 bases 03; 06 off `master`, LAST. FINAL PR = 06, HELD for Han. (SG-04 builds the quiz gate; it does NOT apply to THIS run's own final PR , circularity; future runs only.)

PER SUB-GOAL (deps: 04 needs 02+03; 05 needs 02+03; 06 needs ALL; 01/02/03 independent):
- `bash lib/lane-classify.sh classify "<sub-goal>"`, run that lane. `/spec` then `/spec-validate` BEFORE code; each design-bearing sub-goal writes its OWN `## Design` block (dogfood SG-01 once it merges, else per ADR-0031).
- Build with `/kit:execute` (V-model fires). Converge verify->fix->re-verify to the named Proof (bounded); never check a box on a failing proof.
- Over-test substantial sub-goals: `/kit:test-plan` matrix, risk-matched test modes, COVERAGE DELTA as a named proof-of-done row; trivial keeps its Done-line.
- Every named negative control is load-bearing (01 refuse-empty-Design + obvious-collapse · 02 obvious-not-significant · 03 grounded-in-diff · 04 grounded + wiring · 05 non-significant-excluded + skill-reuse · 06 over-claim). A proof missing its NC is a failing proof.
- Record gates via `bash lib/gate-ledger.sh record` with PER-GATE reasons. Branch `feat/ug-NN-<slug>`. ROADMAP line -> `PR #N` on open; `[x] ... merged <sha>` on merge.

TIER-4 CLOSE (after 01-05 merge, before 06/final): integration-verifier against the objective + a NO-ORPHAN CHECK over every artifact (Design block, significance-classify, /kit:explain, quiz gate, batch flow) , defined-but-never-dispatched = blocking, a WORKFLOW/AGENTS claim with no dispatch path = blocking (c6fbd99 class); `/kit:review-team` with the deep `security-reviewer` lens; `advisor` in BOTH modes (over-suggest -> NOTES `## Proposed additions`). Fix, re-verify, hold the final PR, then the visible close per OPERATE.md.

HARD RULES + CLOSE-OUT per OPERATE.md. PR audits target `dwarvesf/dwarves-kit`.

STOP. Success = 01-06 merged (06 held as final), TIER-4 clean. Also stop: gate-zero unmet, blocker with unchanged prerequisite, token out.
