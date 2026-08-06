# 0026. Co-located proof-of-done + table-first review layout (additive)

Date: 2026-06-09
Status: Accepted
Relates-to: ADR-0025 (proof-of-done ship gate, the gate this rides on), the proof-of-done convention (docs/verification/README.md), lib/gate/proof-ledger.sh (the diff-keyed gate), ops-toolkit SPEC-016 (the consumer adoption that drove this)

## Decision (one line)

Bless a co-located `tools/<name>/docs/proof-of-done.md` as a first-class home for a tool's canonical proof (packaged with the code), and add an optional **table-first review layout** for any proof, both ADDITIVELY: every existing shape (`docs/verification/<slug>/{test-design.md, runs/}`, the flat `<slug>.md`) and the gate markers stay exactly as they were.

## Context

The canonical convention prescribes `docs/verification/<slug>/{test-design.md, runs/}` at the repo root and lists co-located `tools/<name>/docs/proof-of-done.md` as **back-compat**. Two things pushed back:

1. **Packaging.** For a tool in a `tools/<name>/` monorepo (ops-toolkit), a proof detached at the repo root drifts from the code it proves and is easy to miss in review. Teams want the proof to travel WITH the tool.
2. **Review ergonomics.** The run-record shape (`runs/<ts>.md`: Command/Exit/Output/Verdict) is optimized for an immutable execution log, not for a reviewer scanning "what does done mean here, was it met, when, and how do I re-run." A reviewer wants acceptance criteria first, then implementation, then a timestamped confirmation table.

The gate (`lib/gate/proof-ledger.sh`, ADR-0025) already accepts a file named `proof-of-done.md` anywhere via the regex `(^|/)proof-of-done\.md$`. So co-location is already gate-legal; it was just labeled "back-compat." This ADR promotes it and adds the review layout, without changing the gate or breaking any consumer.

## Decision

1. **Co-located proof is first-class for tool work.** For a tool living at `tools/<name>/`, its canonical proof MAY live at `tools/<name>/docs/proof-of-done.md`. It is gate-visible via the `proof-of-done.md` filename (not via a repo-root path). Optional immutable history co-locates at `tools/<name>/docs/runs/<ts>.md`; optional design at `tools/<name>/docs/test-design.md`. The repo-root `docs/verification/<slug>/` layout remains equally valid (use whichever fits; co-location is encouraged for `tools/` monorepos, the root layout for feature branches without a tool home).

2. **The filename is load-bearing.** Because the gate's only co-located match is a file named `proof-of-done.md`, a co-located `runs/` directory is invisible to the gate. So a co-located canonical proof MUST be the `proof-of-done.md` file itself and MUST carry the literal gate markers (`Command:`, `Exit:`, `NEGATIVE CONTROL`, `rollback` / `[UNAVAILABLE`) in its body.

3. **Optional table-first review layout.** Any proof (co-located or root) MAY use a table-first layout: Acceptance criteria (table) -> Implementation -> Confirmation (timestamped run table) -> Run detail (the gate markers, full depth) -> Reproduce. The tables are a human review surface; the run-detail section keeps the literal markers so the gate is unaffected. The existing run-record shape stays valid for repos/teams that prefer it.

4. **Work-type dialects (one spine, the body adapts).** The same proof spine carries four common shapes: one-shot CLI / data tool (green + negative control), stateful daemon / service (liveness + kill-to-RED + restore/rollback), recurring action / loop / workflow / cron (an append-only run ledger + a monitoring signal), and eval / experiment (a thin pointer to `experiments/<slug>/TEST-REPORT.md`, which stays the single source of measured numbers).

5. **Strictly additive.** No gate change. No marker change. Every shape that validated before still validates. Consumers (dfoundation, trading, ops-toolkit) need no migration; they adopt the new shape only when they choose to.

## Alternatives considered

- **Replace the root layout with co-location.** Rejected: breaks existing proofs in consumer repos and the kit's own worked examples. Additive is the only safe upstream.
- **Leave co-location as "back-compat" only.** Rejected: that wording discourages the very packaging teams want; it was already gate-legal, so the cost of blessing it is zero.
- **Make the gate parse a co-located `runs/` directory.** Rejected here (a gate change with real blast radius across every consumer). Out of scope; the `proof-of-done.md`-as-canonical path solves the packaging need without touching the gate.
- **Ops-toolkit-only convention (no upstream).** Rejected by the consumer (ops-toolkit SPEC-016 D-016-B): a local fork drifts from the kit worked examples; the format belongs in the canonical.

## Consequences

- Tool monorepos can keep proof packaged with code; reviewers get a top-down scannable proof.
- The canonical README now documents two equally-valid homes (root layout, co-located) and an optional presentation layer; authors pick per context. Slightly more surface to explain, mitigated by the work-type dialect table.
- Because nothing about the gate or markers changed, this ADR is reversible by reverting the docs alone; no consumer proof is invalidated either way.
- Worked reference: ops-toolkit `tools/{zedra-deploy,growatt-pull,spec-to-cli}/docs/proof-of-done.md` (SPEC-016).
