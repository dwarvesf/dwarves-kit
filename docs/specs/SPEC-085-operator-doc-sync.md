# SPEC-085: Operator doc sync (README / WORKFLOW / AGENTS vs shipped reality)

Status: SHIPPED
Date: 2026-06-11
Lane: normal (classified: normal)
Type: doc (standalone-revision path, WORKFLOW `## Type loops`)
Board: ID-070 (2026-06-10 intake item 7; ran last, after ID-065..069 + 033 + 036)

## Audit findings (the sweep's input)

| Doc | Finding | Class |
|---|---|---|
| README | Hooks summary says 14; `hooks/*.sh` = 16; `ship-gate` (a HARD hook) and `codebase-index` rows missing | WRONG COUNT + missing rows |
| README | Commands summary says 22; rows = 23; `commands/*.md` = 25; `adopt` + `test-plan-review-team` rows missing | WRONG COUNT + missing rows |
| README | `context-readiness` row predates SPEC-083 (no board awareness, "suggests next command") | stale |
| README | `/kit:review-team` rows (x2) predate the absorption set (no confidence gate / validators) | stale |
| README | `/kit:verify` rows (x2) predate SPEC-077 (no INCONCLUSIVE verdict) | stale |
| WORKFLOW | "detects state ... suggests next step" predates SPEC-083 | stale |
| WORKFLOW | command-map review-team row predates the absorption set | stale |
| AGENTS | clean; every spec updated it in-branch | none |

Root cause of the count drift: the architecture.md inventory tables carry
parity pins; the README tables never did.

## Decision

1. Fix the two counts, add the four missing rows, refresh the six stale
   descriptions, touch nothing else (surgical; the narrative layer was
   rewritten 2026-06-10 and stands).
2. **Two parity pins in test-meta.sh**, both sides computed: README hooks
   summary count == `hooks/*.sh` count AND row count; README commands summary
   count == `commands/*.md` count AND row count. The exact anti-drift trick
   the architecture tables already use.
3. Content pins: ship-gate row present; adopt + test-plan-review-team rows
   present; README context-readiness row carries the board token.

## Acceptance criteria

- AC1: README hooks block: summary (16) == files == rows; ship-gate +
  codebase-index rows present.
- AC2: README commands block: summary (25) == files == rows; adopt +
  test-plan-review-team rows present.
- AC3: six stale descriptions refreshed (board-aware context-readiness,
  confidence-gated review-team, INCONCLUSIVE verify; WORKFLOW x2).
- AC4: parity pins computed both sides (no hardcoded 16/25 in the pin).
- AC5: suites green; NC: delete one README hook row -> parity pin RED.

## Tasks

- [x] Failing-first pins (2 parity + 3 content)
- [x] README count + row + description fixes
- [x] WORKFLOW two description fixes
- [x] NC measured; suites green

## Verification

- 7 pins failing-first (7 RED) -> green; parity computed both sides.
- NC: ship-gate row deleted -> 2 RED (row parity 16 vs 15 + content pin) ->
  restored.
- Suites: meta 500/500, hooks 426/426, e2e 20/20.

## Review

Date: 2026-06-11. Single combined lens (doc-only diff), 8/10 pre-fix. MEDIUM:
the new README pointer line hardcoded the class breakdown (5/3/8), the exact
count-trap doctrine; numbers dropped, the architecture parity pin owns the
counts. LOW (accepted): README hook rows order by class loosely, not pinned;
cosmetic. Verdict: SHIP.
