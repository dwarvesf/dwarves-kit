# SPEC-111: starter role-specialized agent roster

Status: VALIDATED
Lane: full
Type: spec-feature

## Problem

`commands/execute.md` step 2b-0 dispatches a task's IMPLEMENTER specialist by: `role-classify.sh
classify` -> a domain, then "reuse an existing specialist if a predefined agent fits" , but the
FIT is a LEAD JUDGMENT with no deterministic domain->agent lookup, so the reuse branch rarely
hits and 2b-0 falls through to Mode-C synthesis even for common domains. There is no starter roster
of domain specialists, and no reconciliation of the static "known-domain" reuse path vs SPEC-089's
dynamic Mode-C synthesis (the long tail).

The mega-goal (roadmap: ops-toolkit `_meta/megagoals/kit-face/`, assumptions 09) resolves this: a
starter roster , one specialist per `role-classify` domain, mixed reviewer/worker by fit, each
gated + provenance-stamped , each with a LIVE dispatch path, and the SPEC-089 boundary stated.

## Solution

**Two agent types, two live dispatch paths (spec-validate F1: 2b-0 reuse dispatches the task
IMPLEMENTER, so a read-only reviewer does NOT belong there):**

- **WORKER agents** (write-capable: the value is DOING) are the 2b-0 reuse targets , the implementer
  slot. A `role-classify.sh agent-for <domain>` lookup makes the reuse deterministic.
- **REVIEWER agents** (read-only: the value is JUDGMENT) are dispatched by `/kit:review-team` as
  opt-in DOMAIN lenses (when the diff touches that domain) , the review slot, where read-only fits.

Both are live dispatch paths, so the anti-orphan WIRING GATE (ROADMAP 13/14: "defined-but-never-
dispatched = blocking") is satisfied for BOTH types; the gate's literal "2b-0 reuse" wording was
written assuming workers, and is reconciled here: workers -> 2b-0, reviewers -> review-team.

1. **`role-classify.sh agent-for <domain>`** prints the WORKER agent name for a worker-domain,
   EMPTY otherwise. 2b-0 step 2 calls it: `classify` -> domain -> `agent-for` -> non-empty ->
   dispatch THAT worker (reuse HIT); empty -> fall through to Mode-C (unchanged). **`generic`
   returns EMPTY** (spec-validate F2: SPEC-089:79 requires generic to escalate to Mode-C, not
   reuse-hit; a `generic->agent` map would collapse the whole long tail).

2. **Starter roster , one per domain, mixed by fit, existing NOT duplicated:**
   | domain | agent | type | dispatch path |
   |---|---|---|---|
   | db-migration | `db-migration-worker` (NEW) | worker | 2b-0 reuse (`agent-for`) |
   | data-etl | `data-etl-worker` (NEW) | worker | 2b-0 reuse (`agent-for`) |
   | performance | `performance-reviewer` (NEW) | reviewer | review-team domain lens |
   | api | `api-reviewer` (NEW) | reviewer | review-team domain lens |
   | frontend | `frontend-reviewer` (NEW) | reviewer | review-team domain lens |
   | infra | `infra-reviewer` (NEW) | reviewer | review-team domain lens |
   | security | `security-reviewer` (EXISTING) | reviewer | review-team (do not duplicate) |
   | generic | (none) | , | Mode-C long tail (`agent-for`=empty) |

   6 new agents (2 workers + 4 reviewers). Each carries `generated-by:` (SPEC-108) + a one-line
   tools+model justification.

3. **Gating (the effectiveness gate rejects write tools , `tests/test-agent-effectiveness.sh:42`):**
   the 4 REVIEWERS pass the mechanical gate (read-only, valid tier, on-axis name). The 2 WORKERS
   carry `Edit`/`Write` and are gated by the agent-effectiveness AGENT (its "tools
   minimal-yet-SUFFICIENT" lens is role-aware: over-grant is only flagged for a read-only
   reviewer listing write tools, `agents/agent-effectiveness.md:43-49`, so a worker's justified
   write tools pass), dispatched + recorded in the proof. Neither path MODIFIES the validator
   (out of scope). The mechanical gate is invoked locally, not in CI.

4. **`/kit:review-team` domain lenses** , an opt-in step: after the fixed 3 lenses, if the diff
   touches a `role-classify` domain that has a reviewer, dispatch that domain reviewer too. Keeps
   the fixed lenses unchanged (additive).

5. **SPEC-089 boundary** , spec + one WORKFLOW.md sentence: 2b-0's reuse(static-known-worker)-vs-
   synthesize(dynamic-novel) branch is the single router; review-team owns the review-lens roster.
   No second router.

6. **Roster-sync** , each new agent gets a MANUAL.md row + a docs/architecture.md inventory row
   (test-meta.sh fails closed otherwise: MANUAL both directions + architecture row-count == file count).

## Verification

```bash
cd dwarves-kit
# agent-for maps WORKER domains only; reviewers + generic + security -> empty (Mode-C / review-team)
bash lib/classify/role-classify.sh agent-for db-migration   # db-migration-worker
bash lib/classify/role-classify.sh agent-for data-etl        # data-etl-worker
bash lib/classify/role-classify.sh agent-for performance     # (empty: reviewer, review-team lens)
bash lib/classify/role-classify.sh agent-for generic         # (empty: Mode-C long tail, SPEC-089)
# reuse-HIT resolution: a worker-domain task resolves to THAT worker (2b-0 reuse source)
D=$(bash lib/classify/role-classify.sh classify "write a migration to add a column and backfill"); bash lib/classify/role-classify.sh agent-for "$D"  # db-migration-worker
# reviewers pass the mechanical effectiveness gate; workers carry write tools
for a in performance-reviewer api-reviewer frontend-reviewer infra-reviewer; do bash tests/test-agent-effectiveness.sh "agents/$a.md" >/dev/null && echo "$a GATED-OK"; done
grep -qE '^\s*-\s*(Edit|Write)' agents/db-migration-worker.md && echo "db-migration-worker is write-capable"
# roster-sync + frontmatter + lookup all green
bash tests/test-meta.sh
bash tests/test-role-classify.sh   # + the agent-for lookup + generic-empty + worker-domain block
```

## After state

- `lib/classify/role-classify.sh`: `agent-for <domain>` verb (worker-domains -> worker name; else empty).
- `commands/execute.md` 2b-0 step 2: consults `agent-for` for a deterministic worker reuse hit.
- `commands/review-team.md`: opt-in domain-lens step (dispatch a domain reviewer when the diff
  touches its domain); the fixed 3 lenses unchanged.
- `agents/{db-migration,data-etl}-worker.md` (write-capable) + `agents/{performance,api,frontend,infra}-reviewer.md`
  (read-only), each with `generated-by:` + a tools/model justification line.
- `MANUAL.md` + `docs/architecture.md`: roster rows for the 6 new agents.
- `WORKFLOW.md`: one sentence stating the workers->2b-0 / reviewers->review-team dispatch boundary.
- `tests/test-role-classify.sh`: `agent-for` lookup + generic-empty + worker-domain reuse block.
- `docs/verification/role-agents.md`: run-table + per-agent gate result + the reviewer/worker
  on-role fixture dispatch (the real dispatch proof; the lookup proves resolution).

## Scope edges

**In:** the 6 new agents, `agent-for`, the 2b-0 wiring, the review-team domain-lens step, roster-sync,
the SPEC-089 sentence, tests, per-agent gating.
**Out:** the effectiveness validator itself (SG-01, do NOT modify); the provenance emitter (SPEC-108
owns it); dynamic same-run synthesis (stays SPEC-089 Mode C); the fixed review-team 3 lenses.
**Not:** duplicating security-reviewer/code-reviewer; 16 agents; a `generic`->agent map; a second router.

## Open questions

The reviewer/worker split maps to the dispatch reality: WORKERS implement (2b-0), REVIEWERS judge
(review-team). A read-only reviewer in the 2b-0 implementer slot cannot satisfy a task (spec-validate
F1), so reviewers live on the review path. The WIRING GATE's "2b-0 reuse" wording is reconciled to
"each agent has a live dispatch path" (workers 2b-0, reviewers review-team); TIER-4's no-orphan check
verifies exactly that. `generic` stays empty so the SPEC-089 long-tail escalation is preserved.
