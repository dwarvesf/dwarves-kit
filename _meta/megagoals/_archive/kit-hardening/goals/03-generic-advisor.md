# Sub-goal 03: generic advisor (extra lens + over-suggest)

**Merge policy:** auto , the advisor agent + its wiring are testable via fixtures; no human-judgment step to build it.
**Time budget:** 3-4 hours.
**Proof:** run-table , advisor runs in critique mode (P5) at the integration/UAT boundary AND in over-suggest mode (P6) before the final review · it is an EXTRA lens (specialized per-phase reviewers still run) · it passes the 01 effectiveness validator · its model/config knob rides the per-agent cheap-first tiering.
**Depends on:** 01 (gated by the effectiveness validator) + 02 (born under the naming convention as `advisor`).
Model: opus
Effort: high
**Branch:** feat/kit-harden-03-advisor
**PR base:** mega/kit-hardening

## Outcome

One configurable generic `advisor` agent exists with TWO modes: critique (P5) , a uniform extra review lens ON TOP of the specialized per-phase reviewers at the integration + UAT boundary; and over-suggest (P6) , a generative pass that proposes additional ideas/sub-goals to improve the work, surfaced to the human just before the final review. It is a KIT DEFAULT (runs on every applicable run, not opt-in), generated via the shipped meta-agent (`/kit:draft-agent`), and gated by the 01 effectiveness validator.

## Quality bar

The advisor ADDS a lens, it does NOT replace the tailored per-phase reviewers (that tailoring is the kit's value , ADR-0028 2026-07-01 refinement). One agent, two modes , not two agents. Its model tier is a config knob on the existing cheap-first per-agent tiering, so it never silently burns opus on every run.

## How to close the loop

Scaffold the agent via `/kit:draft-agent` (or `lib/`-driven meta-agent for cross-repo), gate it through 01, wire both modes into WORKFLOW.md at the final boundary. Verify:

```
cd dwarves-kit && bash tests/test-advisor.sh          # both modes fire; extra-lens (specialists still run); tier-config honored
bash tests/test-agent-effectiveness.sh agents/advisor.md   # 01 gate passes on the new agent
```

Captured evidence: run-table at `docs/verification/advisor.md` , a critique-mode row (advisor output alongside specialist reviewers), an over-suggest-mode row (proposed additions surfaced pre-final), the effectiveness-gate-pass row.

**Done =** `agents/advisor.md` exists conforming to the naming convention, passes the 01 effectiveness gate, and `test-advisor.sh` proves both modes fire at the final boundary as a KIT DEFAULT without replacing the specialized reviewers.

**Kit-adopted repo? Record the gates.** `bash lib/lane-classify.sh classify "generic advisor agent, two modes, wired as kit-default extra lens"` (expect `full`), record build + review gates via `lib/gate-ledger.sh` before push.

## Handoff on completion

1. Flip 03's box, PR # + SHA.
2. HOT `HANDOFF.md`: next is 04-right-arm-parity (or 05 if both 03/04 done); first action = scaffold `brief-reviewer` via the meta-agent. Pointer: ADR-0028 "Right-arm review parity" + ADR-0029 rename map (the SG-06 rows).
3. WARM `DECISIONS.md`: advisor is the P5/P6 lens, kit-default, one-agent-two-modes; the specialized reviewers are NOT replaced.
4. Report IN records, EXIT.

## Scope edges

**In:** `agents/advisor.md`, both modes, WORKFLOW.md wiring at the integration/UAT boundary, the model/config knob, tests.
**Out:** the specialized per-phase reviewers (untouched , advisor is additive); the right-arm agents (04).
**Not:** making the advisor a hard gate; making it opt-in; a second advisor agent for over-suggest (one agent, two modes).

## Where to look

`agents/` for the meta-agent + sibling agent shape, WORKFLOW.md for the final-boundary phase, the per-agent tiering config (cheap-first `--model` routing), ADR-0028 P5/P6.

## PR body

Adds the generic `advisor` agent (kit-hardening SG-05, ADR-0028 P5/P6): a kit-default EXTRA review lens (critique) + over-suggest pass at the final integration/UAT boundary, on top of the specialized reviewers. Meta-agent-scaffolded, gated by the SG-01 effectiveness validator.

Verify: `bash tests/test-advisor.sh` + the effectiveness gate. Proof: `docs/verification/advisor.md`.

Roadmap: `ops-toolkit/_meta/megagoals/kit-hardening/ROADMAP.md`. Stacked on the integration branch after SG-01 + SG-02.

## Notes

<empty>
