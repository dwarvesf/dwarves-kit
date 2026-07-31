# Spec: shared read-only audit-scanner agent for audit-loop instances
Generated: 2026-07-31
Status: APPROVED (operator pre-approved design; adversarial validate overridden in the gate ledger)
Lane: full

Phase C of the feature-registry program (Phase A: SPEC-219 generator; Phase B: SPEC-218 feature-map skill). Both live audit-loop instances (`skills/doc-drift/SKILL.md`, `skills/feature-map/SKILL.md`) run a Tier-2 evidence-gathering pass by dispatching a general-purpose subagent, which carries the full tool surface: in an unattended cadence run nothing but prose stops that subagent from "helpfully" fixing what it was sent to observe. This spec adds ONE shared agent, `agents/audit-scanner.md`, whose value is ENFORCEMENT: its frontmatter `tools:` roster grants Read/Grep/Glob plus read-only Bash verbs only (modeled on the `code-reviewer` / `research-*` rosters), so it physically cannot write. The dispatching skill hands it a target set + a contract + an evidence-class instruction; it returns per-item findings with quoted evidence and severity in the audit-loop verdict grammar (`docs/patterns/audit-loop.md`), never fixes anything, and never verdicts REMOVE on an untestable referent (UNTESTABLE rule). Both instance skills prefer it for Tier 2; general-purpose stays the documented fallback for runtimes where the kit agent roster is unavailable (e.g. a frozen plugin snapshot).

Design decisions (operator-fixed, recorded here in lieu of a separate design record):
- ONE shared agent, not per-instance scanners: the Tier-2 shape (targets in, evidenced findings out) is identical across instances; the instance-specific half rides in the dispatch prompt.
- Read-only enforcement lives in the frontmatter roster, not in body prose alone; the contract test pins the roster shape the same way `test-test-writer-contract.sh` pins test-writer's.
- The agent proposes, the dispatching skill applies: verdicts flow back as findings; every edit stays on the skill's isolated branch under the skill's own PR gate.
- `sonnet`: per-item evidence judgment against a stated contract is real judgment but pattern-following, same tier as the reviewer/research agents it is modeled on.

## Acceptance Criteria
- [ ] AC-1: `agents/audit-scanner.md` exists with kit-standard frontmatter (name, description, tools, model) and a `tools:` roster of Read/Grep/Glob plus scoped read-only `Bash(...)` patterns only: no bare `Bash`, no `Write`, no `Edit`, no `NotebookEdit`.
- [ ] AC-2: the body states the dispatch contract (receives target set + contract + evidence-class instruction), the per-item output shape (verdict, severity, quoted evidence), and the audit-loop grammar rules: OK/FIX/REMOVE/UNSURE/DANGER, no-evidence downgrades to UNSURE, untestable referents are UNTESTABLE never REMOVE, and it never fixes anything.
- [ ] AC-3: `skills/doc-drift/SKILL.md` step 4 and `skills/feature-map/SKILL.md` step 4 dispatch `kit:audit-scanner` as the PREFERRED Tier-2 scanner, with general-purpose named as the fallback when the scanner is unavailable.
- [ ] AC-4: `docs/patterns/audit-loop.md` names the shared scanner in one line; `docs/FEATURES.md` regenerated (freshness pin green); `docs/workflow-paths.md` gains the agent's section-5 path-index line plus topology placement; README agent count + row and docs/MANUAL.md row added.
- [ ] AC-5: `tests/test-audit-scanner-contract.sh` pins the roster (read-only), the dispatched-by wiring both sides (both skills name `kit:audit-scanner`; the agent names both skills), and the audit-grammar rules, with an in-suite negative control proving the roster check discriminates.
- [ ] AC-6: live negative control recorded in the proof: a write-capable roster mutation on a COPY of the agent file makes the contract test go RED; the tracked file stays green.

## Test plan
Date: 2026-07-31. Dialect: static-contract pinning via the contract test, plus registry/registration pins already in test-meta.

| # | Case | Covers | Expected |
|---|---|---|---|
| 1 | frontmatter roster scan | AC-1 | no bare Bash/Write/Edit; Read+Grep+Glob present; every Bash(...) read-only |
| 2 | in-suite NC: fixture agent with `- Write` + bare `- Bash` through the same check | AC-5 | fixture trips, real file passes (discriminates) |
| 3 | both skills grep `kit:audit-scanner` + fallback wording | AC-3 | present in both |
| 4 | agent body greps both skill names | AC-2, AC-5 | doc-drift + feature-map named |
| 5 | grammar rules greps | AC-2 | verdict grammar + UNSURE downgrade + UNTESTABLE-never-REMOVE + never-fixes pinned |
| 6 | `bash tests/test-meta.sh` | AC-4 | green: FEATURES freshness, README counts/rows, MANUAL row, path-index |
| 7 | live NC on a copy of the agent file | AC-6 | mutated copy RED, tracked file green |

## Verification
```
bash tests/test-audit-scanner-contract.sh && bash tests/test-meta.sh
```
Green. Negative control per AC-6 recorded in `docs/verification/audit-scanner-agent.md`.

## After state
Both audit-loop instances dispatch their Tier-2 evidence pass to a shared agent that cannot write, so unattended cadence runs keep the propose/apply split mechanical instead of prose-enforced. Future audit-loop instances reuse the same scanner by handing it their own four slots.
