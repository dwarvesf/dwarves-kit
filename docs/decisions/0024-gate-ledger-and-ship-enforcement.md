# 0024. Lane-aware gate ledger, action log, and ship-time enforcement

Date: 2026-05-23
Status: Accepted
Relates-to: ID-036 (layering contract: enforced vs advisory), ID-012 P2 (loop QA gate), the lane×phase matrix (WORKFLOW.md), the hands-off-list runtime-extract pattern (lib/dispatch-gate.sh)

## Decision (one line)

A kit run records every gate decision (ran / skipped / why) and every action it took to an operator-readable log, and the **ship/push boundary hard-refuses** when a lane's required gate is missing from that record, unless an explicit override reason is logged. Mid-flight stays LLM-driven and fast; the only hard wall is at the irreversible boundary.

## Context

The kit's quality gates (`/kit:spec-validate`, `task-verifier`, `/kit:review`, `/kit:docs`) are LLM-invoked, while only the safety hooks (`rm`, push-to-main, secret reads) are hard-enforced. A hands-off lead can therefore skip a quality gate and nothing tells the operator. This was observed live: a concurrent trio run skipped the independent `task-verifier` (workers self-ran suites instead) with no surfaced record, and the operator could not answer "what did it check, what did it skip, and why" without re-reading the transcript.

The per-lane depth is already designed: WORKFLOW.md's **lane×phase depth matrix** assigns every (phase, lane) cell `measure-twice` / `run-lite` / `skip`. What is missing is (1) a machine-readable read of that matrix, (2) a record of what each run actually did against it, and (3) enforcement at the one boundary where a miss is irreversible.

## Decision

1. **The lane×phase matrix is the single source, made machine-readable.** A new `lib/gate-ledger.sh` parses the matrix at runtime, exactly as `lib/dispatch-gate.sh` extracts the hands-off list from WORKFLOW.md (no second copy of the mapping). A cell of `measure-twice` means the gate is **required** for that lane; `run-lite` means recommended; `skip` means not applicable. A meta-test asserts every cell is one of the three tokens so the parser cannot silently misread.

2. **Every run writes a gate ledger and an action log**, extending the existing log infra (`$DWARVES_KIT_LOG_DIR`, the append-only `ts | STATUS | detail | pwd` format that already redacts command bodies). The **gate ledger** is per-run (keyed by spec/branch) and records each phase as `ran` / `skipped` with a reason. The **action log** is append-only and records the lead's and agents' actions. Reusing `$DWARVES_KIT_LOG_DIR` keeps one logging convention (no premature new in-repo store); the dir is configurable, so a project may point it in-repo if it wants the trail versioned.

3. **Enforcement is a hook at the ship/push boundary, not command prose.** A check that lives only in `commands/ship.md` is itself LLM-skippable, the exact failure this ADR exists to prevent. So the hard refuse rides on the push/PR boundary (the push-to-main hook family): it reads the lane's `measure-twice` gates from the matrix and the run's ledger, and **blocks** if a required gate has no `ran` entry. An **override** is an explicit logged reason in the ledger (operator-authored); with it, the push proceeds and the override is part of the audit trail.

4. **This is the ID-036 layering bend, scoped minimally.** Previously: hooks enforce only safety/irreversible outcomes; quality gates are advisory. Now: hooks ALSO enforce gate-completeness, but ONLY at the irreversible ship/push boundary and ONLY for the lane's `measure-twice` gates. `docs/PHILOSOPHY.md` and `commands/kit-health.md` are reworded so the bend is deliberate, not a silent breach of "guardrails over guidance".

## Alternatives considered

- **Hard-block at every phase.** Rejected: friction at reversible mid-flight steps, and it pushes hard enforcement into every command. The maintainer chose ship-only blocking.
- **Announce-only, never block.** Rejected: a determined hands-off run still skips everything, only visibly. The operator wants a wall at ship, not just a receipt.
- **A new in-repo `.kit/runs/` ledger store.** Deferred (no premature convention): reuse `$DWARVES_KIT_LOG_DIR`, which already has the dir + redaction logic; revisit if a project needs the trail git-tracked.
- **A separate config file for the lane→gate map.** Rejected: duplicates the matrix. Parse the matrix; it stays the one source.

## Consequences

- New `lib/gate-ledger.sh` (parse matrix, read/write ledger + action log). Gate-running commands append a `ran` entry; the push/PR hook enforces.
- `docs/PHILOSOPHY.md` + `commands/kit-health.md` record the hooks-also-enforce-gate-completeness-at-ship bend (the ID-036 hooks-fallback layer, previously open).
- `tests/test-meta.sh` + `tests/test-hooks.sh` pin: matrix cells are all valid tokens; the ledger + action log are written; a skipped required gate is recorded `skipped`; the push hook refuses on a missing required gate and proceeds with a logged override.
- The lane×phase matrix gains a machine contract (the token guard), so future edits cannot break the parser silently.
- **Override threat model (honest scope).** In a fully autonomous `bypassPermissions` run the agent can run any command, so it can also write the override entry. The guarantee is therefore **block-by-default + every skip and every override recorded and auditable**, not cryptographic prevention. True prevention still requires a human at the ship boundary. This matches the goal's wording ("cannot ship unless an override is logged") and is the realistic ceiling for an in-repo bash mechanism; we do not over-claim a hard stop the runtime cannot give.
- Source: ID-036 + ID-012 P2. Reuses the WORKFLOW-extract pattern (ADR-0019/0020 lineage) and the existing hook log infra; no net-new logging convention.
