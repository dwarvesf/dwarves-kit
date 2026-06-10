# SPEC-057: Taxonomy expansion, 6 -> 11 work types + universal done-first

Status: SHIPPED ([Unreleased])
Lane: full (kit-machinery: lib/ classifier touched)
Backlog: ID-048
Branch: feat/north-star-06-taxonomy
Relates-to: PHILOSOPHY §6 N1/N3, SPEC-054 (type loops), SPEC-055 (board), SPEC-056 (dialects), SPEC-031 (V-model)

## Problem

An evidence sweep over the operator's full LAB_LOG (all entries + the skills inventory) found
the 6-type taxonomy covers only ~47% of real work; eight recurring kinds (51 entries, ~43%)
fall through to `spec-feature` and get squeezed into the code cycle: incident response (6
entries + 7 filed INC records), state reconciliation/cleanup (9), recurring operations
(payroll/recon/radar), planning (5 + the maintainer's explicit weekly-planning case), learning
tracks (7). A planning task classifying as spec-feature/normal is a misfit the maintainer hit
directly.

Second gap (the maintainer's assertion, verified correct): N3 requires done defined BEFORE
execution for EVERY type, but the Type-loops table had no universal phase 0 and `/kit:assign`
printed the proof contract without requiring a `Done =` line in the draft.

## Decision

**5 new types** (each = classifier rule + registry row + WORKFLOW loop + §5b dialect):
incident (stateful), reconcile (behavioral), operate (stateful), planning (inert),
learning (inert). Precedence: incident first (alert language never falls through);
learning/planning/operate are material/schedule-anchored so they cannot steal build phrases
("plan the schema migration rollout" still -> migration, pinned); reconcile before doc/migration.

**3 deliberate folds** (considered-and-rejected rows):
- deployment -> stays `migration` (same dry-run + rollback shape; added `launchd|daemon|provision` keywords so it stops falling through to spec-feature).
- agent-org config -> rides `spec-feature` lanes (the lane hard-gates catch the risky cases).
- discovery/audit -> splits by intent: "what exists" -> research; "records vs reality" -> reconcile.

**Universal done-first**: Type-loops phase 0 stated once above the table (proof contract +
dialect test design BEFORE any phase); `/kit:assign` drafts MUST carry `Done =`; SPEC-031 notes
the right arm is type-agnostic.

## Acceptance criteria

- AC1: 11-type truth table green (5 new + 6 regression + 1 precedence edge) in tests/test-hooks.sh.
- AC2: registry/loops/dialects at 11/11/11 with the parity pin (a half-added type goes RED).
- AC3: `proof-gate.sh contract` composes correctly for a new type (incident prints its INC artifact + owner).
- AC4: assign requires `Done =`; WORKFLOW states phase 0; SPEC-031 carries the type-agnostic note.
- AC5: negative controls recorded (keyword rule commented -> truth-table RED; dialect row dropped -> parity RED).

## Test plan

| # | Case | Proof |
|---|---|---|
| 1 | truth table | 12 TTYPE assertions in tests/test-hooks.sh (5 new, 6 regression, 1 anchor edge) |
| 2 | parity | SPEC-057 parity pin in tests/test-meta.sh counts registry=loops=dialects=11 |
| 3 | contract composition | `bash lib/proof-gate.sh contract "triage the INC-008 alert"` -> type=incident + INC artifact |
| 4 | done-first wiring | `grep -c 'Done =' commands/assign.md` >= 1 AND `grep -c 'Phase 0 is universal' WORKFLOW.md` == 1 |
| 5 | negative controls | comment the incident rule -> its test RED; delete the reconcile dialect row -> parity RED; restore both (recorded in the build gate) |

## Rollback

`git revert`. Classifier additions + doc/table rows; parser column-count unchanged; no host state.
