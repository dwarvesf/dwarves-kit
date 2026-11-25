# WORKFLOW.md: the cycle, the lanes, the gates

> Agent-facing contract. Read after CLAUDE.md. It names the lifecycle, routes
> work by risk, and points at the guardrail that enforces each boundary.
> It suggests and routes; it does not block. The four hard stops, where an
> autonomous run stops for a human, are the safety-gate hook, the push-to-main
> blocker, the anti-rationalization Stop hook, and the verification pipeline.
> The rules code blocks on, each with a proving test, are listed in `docs/reference/hard-rules.tsv`.

## Required reading
`AGENTS.md` is the front door and owns the read-order; it is the single source.
Read `AGENTS.md` zone 1 ("Read in this order") for the full ordered list, then
return here.

**Full content:** [`docs/WORKFLOW.md`](docs/WORKFLOW.md) -- the phase cycle, the
V-model lens, the lane×phase depth matrix (lanes: `tiny` / `normal` / `full` /
`bug` / `backfill`; phases: grill, think, spec, spec-validate, test-plan,
execute, review, docs, ship, retro), gate ledger + ship enforcement, the
understanding axis, mega-goal delegate execution, and the flow/loop ASCII
reference all live there. If you grepped THIS file for a lane or phase and
landed here: the matrix you want is in `docs/WORKFLOW.md`, one hop, no further. This root file is a thin entry point kept short so a
newcomer isn't buried on arrival; every code/test reader in this repo resolves
the bulk at `docs/WORKFLOW.md` directly (SPEC-185).

## The learning boundary

This kit owns the first row; the other rows are the kits it hands off to. The decision behind the split is ADR-0036 in dwarves-kit.

| Kit | Learner or plane | What it owns | The seam it fills |
|---|---|---|---|
| dwarves-kit | the process plane: the system changes | gates, ledgers, the landing step, `reflect`, and the understanding gate (the DEBT record, the nudge, `explain` and `quiz-gate` as entry points that gather the material) | none; it declares the seams the other two fill |
| learning-kit | a human learning: paying an understanding debt, or studying outside material | the `understand` teacher, the `study` lane, the one concept ledger and its flush | `understand.teach`, `wrap.after` |
| context-kit | the knowledge tree a human and an agent share | writing knowledge into the tree and the tree's page contract | `knowledge.root` |

