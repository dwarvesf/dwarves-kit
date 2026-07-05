# Spec: docs + wiring, honestly (ledger-observatory SG-05, final)
Generated: 2026-07-04
Status: VALIDATED
Lane: normal (lane-classify.sh returned `normal`)
Depends-on: SPEC-126 (schema, merged b4ff175e), SPEC-127 (etl-cli, merged e6ff875b), SPEC-128
(render-skill, merged 7f8f7e2c), SPEC-129 (feedback-loop, merged a0806ff3). All four are shipped
on `main`; this spec is docs-last by design (goal file: "reflect the final wired state").

## Problem

`tools/ledger-observatory/` is fully built (schema + ETL/CLI + render skill + feedback loop, all
merged) but its two agent-facing surfaces lie about that state:

- `skill/SKILL.md` (the interface the agent actually reads mid-session) tells the agent the
  feedback loop is "a separate, future sub-goal (04-feedback-loop), not built yet" and that a raw
  grep over `| DEBT |` lines is "the closest available signal" for debt, when `ledger anomalies`
  already supersedes both.
- `README.md`'s status table says "04-05 ... pending" when 04 is merged (a0806ff3) and this PR is
  05 in-progress.

Nothing currently PROVES the tool's claims dispatch. TIER-4 review (per the ROADMAP's binding
"cross-cutting WIRING GATE" assumption, mirroring kit-hardening bug c6fbd99) found this exact bug
class: a doc can claim an artifact is live when nothing actually invokes it, and nothing catches
that. There is also no single front door: `README.md` exists but is not yet the finished
front-door doc per `ops-tool-docs`, and the `docs/proof-of-done.md` multi-feature index needs its
final row (it already has all 4 rows from prior sub-goals landing their own proof updates, but
needs confirmed-accurate as of today).

## Solution

### Approaches considered

1. **Fix the docs in place + add one no-orphan test file that greps the shipped source for each
   documented claim's live counterpart, plus an over-claim NC that mutates a temp copy of README
   and asserts the check catches it (CHOSEN).** Cheapest, matches the existing tool's test-file
   convention (`tests/test-*.sh`, self-contained bash + fixtures), and the NC only needs to prove
   the check is falsifiable, not exercise a second full harness.
2. **Build a generic "doc-claim vs. dispatch" linter reusable across ops-toolkit tools.**
   Rejected for THIS PR: over-scope (goal file Scope-edges "Out: a doc surface the tool does not
   need"); a generic linter is exactly the kind of speculative abstraction the repo's "Simplicity
   first" rule warns against for a single-tool docs PR. Noted as a NOTES.md proposed addition
   instead (not in this spec's scope) is NOT taken here either, since it wasn't in the dispatch's
   list; kept local to this tool.
3. **Skip the honesty fixes to `skill/SKILL.md` since the goal file's Scope-edges omit it.**
   Rejected per the dispatch note overriding the goal file: the skill is the primary agent-facing
   surface and leaving it stale defeats the sub-goal's purpose (see implementation-notes
   2026-07-04 09:00 entry for the full reasoning).

### Chosen approach + why

Approach 1. It is the smallest change that makes every doc claim falsifiable against the real
CLI/skill source, matches the tool's existing test shape, and does not invent new infrastructure
for a single-PR concern.

### Extensibility & boundaries

- If a 6th feature lands later (SG-06+), the no-orphan test's claim list grows by one entry per
  new `@app.command()` the README documents; no structural change needed.
- Unit boundary: `tests/test-docs-wiring.sh` owns ONLY the wiring/presence/over-claim checks. It
  does not re-run the 4 existing feature test suites (schema/etl-cli/render-skill/feedback-loop);
  those stay each feature's own proof.

### Architecture

obvious: a documentation + one bash test-file change to an already-shipped tool; no new
component, no schema change, no external integration, no irreversible decision. Collapses per the
Design block's own instruction for non-design-bearing work.

## Design

obvious: docs-only change to an existing, fully-built tool. No new component, no control-flow
change, no schema/data-model change, no external integration. The one "decision" (over-claim NC
mechanism) is recorded as DEC-001 below, not an architectural choice needing a diagram.

## Technical Design

### Interfaces (I/O contract)

- Inputs / consumes: the tool's own shipped source (`src/ledger_observatory/{cli,anomalies}.py`),
  `skill/SKILL.md` frontmatter + body, `README.md`, `tool.toml`, `../../MANIFEST.md`,
  `../../_meta/INVENTORY.md`.
- Outputs / produces: corrected `README.md`, corrected `skill/SKILL.md`, a finalized
  `docs/proof-of-done.md` index row set, corrected `tool.toml`/`MANIFEST.md`/`INVENTORY.md` rows,
  a new `tests/test-docs-wiring.sh`.
- Invariants: the no-orphan test never mutates the real README/SKILL.md/tool.toml (the over-claim
  NC operates on a temp copy only); the test is read-only over every existing feature test file.

### Data model changes
None.

### API changes
None (the CLI's command surface is unchanged by this sub-goal; only docs describing it change).

### UI changes
None.

### Infrastructure changes
None.

## Task Breakdown

### Phase 1: Foundation
- [x] TASK-001: Fix `skill/SKILL.md` honesty issues, remove the "feedback loop ... not built
  yet" line (When NOT to use this skill section) and the frontmatter's "NOT the anomaly/feedback
  loop ... a separate, future sub-goal" clause; fix the debt-signal table row to point at `ledger
  anomalies` instead of a raw `| DEBT |` grep. — acceptance: `grep -c "not built yet\|future sub-goal" skill/SKILL.md` returns 0; the debt row references `ledger anomalies`.
- [x] TASK-002: Fix `README.md` status table (04-05 pending → 04 merged a0806ff3, 05 in-progress)
  and finalize it as the ops-tool-docs front door (read-only-lens contract, all 5 CLI verbs incl.
  `anomalies`, render skill + install path, feedback loop, the 4 honest tradeoffs)., acceptance:
  `grep "04-05.*pending" README.md` returns nothing; `anomalies` is documented as a command; the
  4 tradeoffs appear as prose.

### Phase 2: Core
- [x] TASK-003: Finalize `docs/proof-of-done.md` as the multi-feature index (confirm all 4 rows
  current; do not touch `verification/*` per-feature files)., acceptance: 4 feature rows present,
  each PASS, none of `verification/schema.md`, `verification/etl-cli.md`,
  `verification/render-skill/render-skill.md`, `verification/feedback-loop/feedback-loop.md`
  modified (`git diff --stat` shows no changes under `verification/`).
- [x] TASK-004: Correct `tool.toml` + `../../MANIFEST.md` row + `../../_meta/INVENTORY.md` row to
  drop stale "SG-03/04/05 pending" language., acceptance: no "pending" language referencing a now-
  merged sub-goal remains in any of the three.
- [x] TASK-005: Write `tests/test-docs-wiring.sh`: (a) presence checks (README, proof-of-done,
  tool.toml, MANIFEST row); (b) no-orphan sweep (skill frontmatter trigger phrases present; skill
  body invokes `ledger` CLI verbs that exist in `cli.py`; `ledger anomalies --propose` code path
  feeds the cc-backlog staging buffer, proven by calling `anomalies_mod.stage_proposals` against a
  fixture, same shape as `test-feedback.sh`); (c) over-claim NC (inject a fabricated `ledger foo`
  claim into a TEMP copy of README, assert the check fails on it; assert the check passes clean on
  the real README)., acceptance: `bash tests/test-docs-wiring.sh` exits 0, and the NC section is
  provably load-bearing (a deliberate real-README mutation flips it RED, documented in the run log
  the same way `test-feedback.sh`'s FB-1/FB-2 do).

### Phase 3: Polish
- [x] TASK-006: Append `## Proposed additions` entries (dated 2026-07-04) to
  `_meta/megagoals/ledger-observatory/NOTES.md` per the dispatch's 9-item follow-up list., acceptance: 9 bullet items present under a 2026-07-04 dated entry.
- [x] TASK-007: Record gates via `gate-ledger.sh record`, run the full existing suite (schema +
  etl-cli + render-skill + feedback-loop + the new docs-wiring test) once more as a regression
  check, commit, push, open the PR (base `main`, held), update ROADMAP's 05 line with the PR
  number., acceptance: all 5 suites exit 0; PR opened; ROADMAP line updated + committed.

## After state

- [x] `skill/SKILL.md` makes no false claim about the feedback loop's build status. (Today: it
  claims the loop is unbuilt.)
- [x] `README.md`'s status table shows 04 merged, 05 in-progress. (Today: "04-05 ... pending".)
- [x] `tests/test-docs-wiring.sh` exists, is green, and its over-claim NC is proven load-bearing
  by a deliberate-break run. (Today: no such test exists.)
- [x] The 4 known tradeoffs (dual schema definition, lane-telemetry `_rows()` coupling, static
  `home` attribution + unattributed `repo="?"`, silent source-skip) are stated in prose in
  README.md and/or proof-of-done.md. (Today: not documented.)
- [x] `tool.toml`/`MANIFEST.md`/`INVENTORY.md` carry no stale "pending" language. (Today: they do.)
- [x] A PR is open against `main`, held (not merged), noted as the mega-goal's final PR.

## Acceptance Criteria (global)
- [x] All tasks pass their individual acceptance criteria.
- [x] `bash tests/test-schema-conform.sh && bash tests/test-ledger-cli.sh && bash tests/test-render-skill.sh && bash tests/test-feedback.sh && bash tests/test-docs-wiring.sh` all exit 0 (no regression + the new suite green).
- [x] No existing `verification/*` per-feature proof file is modified.

## Verification

```bash
cd tools/ledger-observatory
bash tests/test-schema-conform.sh
bash tests/test-ledger-cli.sh
bash tests/test-render-skill.sh
bash tests/test-feedback.sh
bash tests/test-docs-wiring.sh
```

## Edge Cases
1. The no-orphan sweep runs before `uv sync` has ever happened on a fresh clone, the test must
   `uv sync` (or otherwise self-bootstrap) rather than assume a warm `.venv`, mirroring
   `test-feedback.sh`'s self-contained fixture pattern.
2. The over-claim NC's injected fabricated command name must not collide with a real future CLI
   verb by coincidence, use an implausible name (`ledger zzz-nonexistent`) and assert on the
   check's PASS/FAIL outcome, not on string content alone.
3. `docs/proof-of-done.md` finalization must not silently drop or reorder the 4 existing feature
   rows, diff against the pre-edit file to confirm only wording/status refresh, not row removal.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Over-claim NC is written vacuously (always passes) | manual deliberate-break run: mutate real README, confirm test goes RED, then restore | required as TASK-005 acceptance; documented in the run log like `test-feedback.sh`'s FB-1/FB-2 |
| Honesty fixes accidentally overstate a tradeoff into a false negative (undersells a working feature) | cross-check each tradeoff sentence against the actual source line it describes before finalizing | manual review pass per tradeoff during TASK-002 |
| `docs/proof-of-done.md` edit accidentally touches `verification/` content | `git diff --stat -- 'tools/ledger-observatory/docs/verification/'` before commit | revert any unintended verification/ change before commit |

## Out of Scope
- Re-implementing or hardening any of 01-04's machinery (schema, ETL/CLI, render, anomaly
  detection), this is a docs-last sub-goal over already-shipped, already-tested code.
- The 9 code-hardening / over-suggestion items from TIER-4 (single column-spec, field-count
  assert, `--repo` group-by, `ledger doctor`, render.py reuse for anomalies output, real e2e
  render CLI tests, staleness-aware re-fire, path-consolidation, privacy-surface tightening), routed
  to `NOTES.md` `## Proposed additions` as follow-up backlog candidates, not built here.
- Installing the render skill into `~/.claude/skills/` (repeat of the existing SG-03 scope edge:
  ops-toolkit ships zero skills directly from a tool PR).

## Touches
tools/ledger-observatory/**

## Decision Log
- DEC-001: the over-claim negative control mutates a TEMP copy of README.md (never the real file)
  and re-runs the same claim-check function against it, asserting a failure; rationale: proves
  falsifiability without any risk of corrupting the real doc mid-test; alternative rejected, hand-editing the real README to a broken state and restoring it (as `test-render-skill.sh`'s
  NC2 does for source code) is unnecessary risk for a doc file and adds restore-on-failure
  complexity for no extra proof value.
- DEC-002: `skill/SKILL.md` is treated as in-scope for the honesty fixes despite the goal file's
  Scope-edges omission, per the dispatch's explicit override (see implementation-notes).
- DEC-003: branch/PR base is `main` (not `feat/lo-04-feedback` as the goal file's stack-era text
  says), since 01-04 are all merged and the stacking branch no longer exists.

## Amendments
(none)

## Review
(not yet run)

## Open questions
(none)
