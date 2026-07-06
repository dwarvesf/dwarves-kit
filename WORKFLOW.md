# WORKFLOW.md: the cycle, the lanes, the gates

> Agent-facing contract. Read after CLAUDE.md. It names the lifecycle, routes
> work by risk, and points at the guardrail that enforces each boundary.
> It suggests and routes; it does not block. The only hard stops are the
> safety-gate hook, the push-to-main blocker, the anti-rationalization Stop
> hook, and the verification pipeline.

## Required reading
`AGENTS.md` is the front door and owns the read-order; it is the single source.
Read `AGENTS.md` zone 1 ("Read in this order") for the full ordered list, then
return here.

**Full content:** [`docs/WORKFLOW.md`](docs/WORKFLOW.md) -- the phase cycle, the
V-model lens, the lane×phase depth matrix, gate ledger + ship enforcement, the
understanding axis, mega-goal delegate execution, and the flow/loop ASCII
reference all live there. This root file is a thin entry point kept short so a
newcomer isn't buried on arrival; every code/test reader in this repo resolves
the bulk at `docs/WORKFLOW.md` directly (SPEC-185).
