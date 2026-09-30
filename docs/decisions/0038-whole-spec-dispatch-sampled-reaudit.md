# 0038. Whole-spec dispatch, one end verification pass, sampled re-audit

Date: 2026-09-30
Status: Accepted (operator approved the direction, design D3, and the validation round 1 revisions)
Relates-to: ADR-0028 (P4 right-arm parity, superseded in part), ADR-0005 (separate verifier, superseded in part), ADR-0023 (supersede convention), `docs/specs/SPEC-369-whole-spec-dispatch.md`, `commands/execute.md`

## Context

`/kit:execute` ran a per-task spine: a persona meta-agent, a worker, a `kit:task-verifier`, an Opus `kit:recheck-verifier` on every PASS, up to two fix rounds, and a human checkpoint per phase. A medium full-lane feature cost about 56 dispatches (an estimate, not a measurement; the A/B run in the spec tests it). The worker template also ordered the builder to expand its task into bite-sized steps, a sequencing script a capable builder no longer needs.

Two facts constrain the fix. The recheck catches rarely but not never: two recorded FAIL:fixable catches across 33 re-audited PASS lines. The per-task criterion check catches real defects that a green suite misses, and `kit:integration-verifier` does not re-check per-task acceptance.

## Decision

1. One builder gets the whole spec as a brief: goal, acceptance, routes, territory, and a standing grant to navigate. A split needs a named reason from a closed list. More than 6 tasks splits up front; a builder near its context limit returns `PROGRESS:` and a continuation builder takes the rest.
2. The per-task `kit:task-verifier` dispatch becomes ONE pass over every task's criteria at the end of the build. Integration and acceptance verifiers follow. The criterion check survives; only its per-task placement goes.
3. The recheck is sampled, not deleted. The run is sampled when `cksum` of HEAD at the first end-verifier dispatch is divisible by `execute.recheck_sample` (default 5, root-only). Every `(self-attested)` row is rechecked on every run. A `(lead-run)` row cannot be rechecked and is tagged as unaudited.
4. The persona meta-agent dispatch and meta-agent Mode C are removed. `role-classify.sh agent-for` stays as a zero-dispatch builder lookup.
5. A build that cannot meet a criterion after the fix loop ends `Result: PARTIAL`, names the unmet criterion with `file:line`, and routes the gap as a follow-on.

## Consequences

- A defect surfaces at the end, not after the task that caused it. Per-task commits localize it, and the fix loop (max 2) still runs.
- Sampling can miss a fabricated PASS. `recheck_sample = 1` restores full coverage, and the ledger records each sampling decision so it can be recomputed.
- `commands/execute.md` shrinks by about a third.
- N = 5 and the 6-task threshold are starting values. Tagged runs and the A/B record tune them.

## Supersedes (in part)

- ADR-0028 P4 right-arm parity: "a fresh-context re-audit lens over each right-arm PASS" becomes a sampled re-audit plus every self-attested row.
- ADR-0005: the separate read-only verifier stands; its per-task consequence ("after a worker subagent completes a task") becomes one pass over every task's criteria at the end of the build.
