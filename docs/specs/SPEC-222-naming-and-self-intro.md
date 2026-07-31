# Spec: naming reconciliation scan + command self-intro convention
Generated: 2026-08-01
Status: APPROVED (operator pre-approved design in the dispatch brief; adversarial validate skipped in the gate ledger)
Lane: full

Two related deliverables in one cycle, both about a new user knowing what a thing is called and what is running.

**A. Naming reconciliation scan (audit-loop one-shot).** Item set: every feature name + the taxonomy vocabulary across `docs/FEATURES.md`, `agents/`, `skills/`, `commands/`, `docs/architecture.md`, `docs/WORKFLOW.md`, `docs/glossary.md`, `docs/verification/task-types.md`. Contract: names follow consistent conventions. Scanned dimensions: suffix-per-role-class (-verifier / -reviewer / -scanner / -writer / -worker / -agent / -team / research-*), lens-vocabulary drift across command bodies, stage/leg/phase terminology (ADR-0034 stragglers), the recent adoptions (wayfind, prototype, audit-scanner, feature-map, doc-drift, loop-engineering) against the older grain, and glossary coverage of recent terms. VERDICT DISCIPLINE (operator-fixed): actual feature renames are report-only PROPOSALS with grep blast-radius counts, never applied; only zero-break fixes land (doc-prose vocabulary drift, glossary additions, description-field wording).

**B. Self-intro convention.** When a kit command or dispatched agent starts, the user sees one line of what is running and why. Leanest durable design: the convention lives in the operate-contract `AGENTS.md` (section "## Self-intro"): every `/kit:` command opens its first reply with `[kit:<name>] <one-line purpose>` derived from its own frontmatter `description`; every dispatched agent's report opens the same way. Backed by a test-meta pin, wired concretely into the three highest-traffic entry commands only (`start.md`, `assign.md`, `execute.md`), and documented with one line in the docs/MANUAL.md Conventions section. **Remaining commands adopt on next touch; the AGENTS.md contract covers them meanwhile** (deliberately not churned across all command files in this cycle).

Design decisions (operator-fixed, recorded here in lieu of a separate design record):
- Report-only for renames: a rename's blast radius (cross-referenced in FEATURES.md, tests, docs, dispatch prompts) makes any applied rename a breaking change; the scan produces evidence + counts, the operator decides.
- Convention-in-contract over per-file churn: one AGENTS.md section + 3 concrete wirings demonstrates the banner without touching all command files; the frozen-plugin-snapshot lag means mass wiring would not surface faster anyway.
- Evidence passes dispatched to the shared read-only audit scanner per SPEC-220; when the agent roster is unavailable (frozen plugin snapshot), the documented read-only general-purpose fallback applies.

## Acceptance Criteria
- [ ] AC-1: `docs/research/2026-08-01-naming-reconciliation.md` exists with a findings table (finding, evidence quote, verdict OK / FIX-applied / PROPOSAL-for-operator), covering all five scanned dimensions, with grep reference counts on every rename proposal.
- [ ] AC-2: every applied fix in the report is zero-break (doc prose, glossary entries, description wording); no feature file is renamed, no identifier referenced by code or tests changes.
- [ ] AC-3: `AGENTS.md` carries a "## Self-intro" section stating the `[kit:<name>] <one-line purpose>` banner rule for commands and dispatched agents, sourced from frontmatter `description`, with the next-touch adoption note.
- [ ] AC-4: `commands/start.md`, `commands/assign.md`, `commands/execute.md` each open their body with the concrete one-line self-intro instruction (start.md's `--brief` mode exempt: its one-line contract wins).
- [ ] AC-5: `tests/test-meta.sh` pins AC-3 + AC-4 (AGENTS.md section + banner format; the three command wirings) and the suite is green.
- [ ] AC-6: docs/MANUAL.md Conventions section documents the banner in one line.

## Test plan
Date: 2026-08-01. Dialect: reconcile-type inventory-with-verdict (task-types §reconcile) + static-contract pinning via test-meta.

| # | Case | Covers | Expected |
|---|---|---|---|
| 1 | research doc exists, has verdict column + all 5 dimensions | AC-1 | present |
| 2 | `git diff` shows no renamed feature files; applied fixes are docs/glossary-only prose | AC-2 | zero-break |
| 3 | test-meta Self-intro block: AGENTS.md section + `[kit:<name>]` format pin | AC-3, AC-5 | PASS |
| 4 | test-meta per-command banner pins (start/assign/execute) | AC-4, AC-5 | PASS x3 |
| 5 | `bash tests/test-meta.sh` full suite | AC-5 | green, no regression |
| 6 | negative control: strip a banner line from a wired command -> test-meta RED -> restore -> green | AC-5 | discriminates |

## Verification
```
bash tests/test-meta.sh
```
Green. Negative control per test-plan row 6 recorded in `docs/verification/naming-and-self-intro.md`.

## After state
- A dated naming-reconciliation report exists under `docs/research/` with every finding evidenced and verdicted; rename decisions sit with the operator, safe fixes are already merged.
- The self-intro banner is a pinned operate-contract convention: the three entry commands demonstrate it, test-meta guards it, and any future command touch inherits it from AGENTS.md.
