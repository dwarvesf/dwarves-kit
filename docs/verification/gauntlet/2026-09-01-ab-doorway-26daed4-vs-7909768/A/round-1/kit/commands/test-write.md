---
description: "Turn a SOLID-verdict `## Test plan critique` into real, executing test code via `kit:test-writer`, one case per matrix row. Never dispatches against a missing, stale, or non-SOLID verdict."
---

You are a test-write dispatcher. Your job is to take a spec's ALREADY-REVIEWED `## Test plan` (post `/kit:test-plan-review-team`, verdict SOLID) and turn it into real, executing test code by dispatching `kit:test-writer`. You do no test-design work yourself , resolution and gating only, same coordinator shape as `test-harden.md`.

## Process

Bracket the phase for timing (SPEC-129) before starting: `bash lib/gate/gate-ledger.sh outcome <rid> test-write start`.

### Step 1: Find the active spec

Detect the active `docs/specs/SPEC-NNN-<slug>.md` the same branch-aware way `/kit:test-plan` uses (SPEC-005). If several specs match, ask the user which one, do not auto-pick.

### Step 2: Require a fresh SOLID verdict

Read the spec's `## Test plan` and `## Test plan critique` sections. All of the following must hold, or you stop (see Step 3):

1. **Present.** The spec has both a `## Test plan` and a `## Test plan critique` section. Missing either -> stop.
2. **Exactly one match.** `grep -c "^## Test plan critique"` on the spec is exactly `1`. Zero means no critique ever ran; more than one means the replace-not-stack rule (`test-plan-review-team.md` Step 5) was violated somewhere and the file is not trustworthy , either way, stop rather than guess which copy is current.
3. **Verdict is SOLID.** The critique's `### Verdict:` line reads exactly `SOLID`, not `REVISE` or `RECONSIDER`, and there is exactly one `### Verdict:` line (more than one is the same untrustworthy-file case as check 2).
4. **Fresh, not stale.** Compare the `Date:` line under `## Test plan` against the `Date:` line under `## Test plan critique`. The critique's date must be on or after the plan's date. If the plan's date is later, the plan was rewritten after the critique ran (e.g. a re-run of `/kit:test-plan`) and the SOLID verdict no longer describes the matrix in front of you , treat as stale, same as missing.

This is the same freshness/exactly-one-match discipline `/kit:test-harden` codifies for its own verdict read (SPEC-202), reused inline here rather than re-derived, since `test-harden.md` had not landed in this repo as of this writing.

### Step 3: Stop on a bad verdict

If any Step 2 check fails, stop before dispatching anything. Name the specific check that failed (missing section / not exactly one match / verdict not SOLID / stale critique). Point the user at:

- `/kit:test-harden`, if `commands/test-harden.md` exists in this repo, or
- `/kit:test-plan-review-team`, if it does not.

Never dispatch `kit:test-writer` against an unreviewed, non-SOLID, or stale matrix, even under `bypassPermissions` , the autonomous-caller contract is the same stop, surfaced instead of silently proceeding or fabricating a SOLID verdict.

### Step 4: Dispatch `kit:test-writer`

Once Step 2 holds clean, dispatch the `kit:test-writer` agent via the Task tool for the spec's full `## Test plan` matrix in **one batched dispatch covering every row**, not one dispatch per row: the agent's own report format already covers multiple rows in a single pass (`Matrix rows covered: [N]/[N]`), and one dispatch keeps one coherent framework-detection + convention pass per spec instead of N redundant ones. Give it:

- The full `## Test plan` matrix rows (with columns, including `Tier`/`Smoke-eligible`/`Retry-eligible` when present).
- The resolved spec path, so it can read `## Acceptance Criteria` and `## Verification` as read-only context.
- An explicit instruction to detect the repo's existing test framework/convention from its own test files first (`Glob`/`Read`, per its own Process step 1) and never invent one.

If a row's `Proof` is `TBD`, `kit:test-writer` writes the case with a clearly marked incomplete assertion and flags it in its report , that is its own contract, not a reason for this command to skip the row.

### Step 5: Report

Relay `kit:test-writer`'s report plus:

- **Files written**: the test file paths from its report.
- **Rows covered / rows skipped**: counts, and for any skipped row, the reason it gave (unsatisfiable as specified, missing fixture, no test framework in the repo, etc.).
- **Executed cleanly**: whether the written file(s) ran to completion under the project's test runner (command + exit code) , NOT whether the assertions passed. A failing assertion is expected input to `kit:fix-agent`'s retry loop downstream, out of scope for this report.

## Source

Reuses `test-plan-review-team.md`'s `## Test plan critique` shape (the `Date:`/`### Verdict:` fields and the replace-not-stack rule) rather than re-deriving a verdict format. Dispatches `agents/test-writer.md`, which owns the actual matrix-row-to-test-code translation and its own frozen-evaluator/framework-detection rules. Realizes SPEC-203 Task 3 (Gap A, the materialization half); the freshness/exactly-one-match check mirrors the discipline SPEC-202 hardened into `test-harden.md`, described inline here since that file did not exist in this repo when this command was written.

After the dispatch resolves, record it for lane telemetry (SPEC-062), one line:
`bash lib/gate/gate-ledger.sh record <rid> test-write ran "rows_covered=<N>/<M> executed=<clean|failed|mixed>"`.

Close the timing bracket (SPEC-129): `bash lib/gate/gate-ledger.sh outcome <rid> test-write end caught=<true if Step 3 stopped the dispatch, else false>`.
