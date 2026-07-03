# SPEC-109: operator-persona design lens

Status: VALIDATED
Lane: normal
Type: spec-feature

## Problem

`/kit:visual-team` runs 5 generic house-style lenses (hierarchy, system-consistency,
accessibility, restraint, expressiveness). An operator often wants the critique through a
specific taste lens , "a HIG-steeped Apple platform designer", "a Linear/Stripe-caliber product
designer". Today there is no way to supply one.

SPEC-016 DEC-003 deliberately REJECTED baked named-person personas (Carmack/Rams as kit-shipped
lenses: "off house-style, taste/maintenance liability"), and SPEC-020 named persona-generation a
non-goal. kit-health check-13 flags "agent-persona theater". A naive persona feature would
re-litigate all three. The distinction the mega-goal (roadmap: ops-toolkit
`_meta/megagoals/kit-face/`, assumptions 06) draws: a **runtime, operator-SUPPLIED** archetype is
categorically different from a **kit-BAKED** persona , the kit ships no persona, and the taste
liability stays with the operator who names it.

## Solution

1. **`/kit:visual-team` accepts `persona: <archetype>`** (via `$ARGUMENTS`). When supplied, it
   dispatches an INLINE 6th lens (SPEC-016 "no new agent files"; borrowing code-reviewer's
   "through the <X> lens only" shape) that returns the SAME contract as the 5 , 2-5 findings, each
   CRITICAL/HIGH/MEDIUM/LOW + concrete fix, plus a 0-10 score , so the merge stays uniform. A 6th
   `### Scores` row (`<persona archetype>: [X]/10`) is appended. 0-or-1 persona per run;
   critique-only. **The 5 existing lenses and the no-arg path are UNTOUCHED.**
2. **`/kit:ui-design` PERSISTS and THREADS it** , `$ARGUMENTS` seeds a `Persona: <archetype>`
   line in the `## UI design` brief (persistence; repeat runs read it without re-supplying), AND
   Step 3 FORWARDS that non-blank `Persona:` line into `/kit:visual-team`'s `$ARGUMENTS` as
   `persona: <archetype>` so the 6th lens actually fires from the ui-design path (threading, not
   just persistence , the wiring gate needs the lens to fire, not merely to be stored).
3. **The governance DEC (DEC-017, this spec; amends SPEC-016 DEC-003).** Records why a runtime
   operator archetype is NOT the baked persona DEC-003 rejected: the kit ships no persona
   (nothing to maintain / no house-style claim), it is operator-supplied per-run (taste liability
   is the operator's), it is critique-only (persona-shaped GENERATION stays a non-goal, SPEC-020;
   the brief's Tone/Differentiation fields own that), and it is an inline lens (no persona-NAMED
   agent file). SPEC-016 DEC-003 gains a one-line amendment pointer.
4. **kit-health check-13 carve-out** , check-13 ("agent-persona theater") gains a clause: an
   operator-supplied `persona:` critique lens is SANCTIONED (inline, no persona-named agent, kit
   ships none), not theater. A kit-health read of the sanctioned path does not flag it.

## Verification

```bash
cd dwarves-kit
# Persona arg + 6th lens present:
grep -qiE 'persona:' commands/visual-team.md
grep -qiE 'through the .*lens only|6th lens|operator persona' commands/visual-team.md
# F1 CONDITIONALITY PIN: the 6th lens AND the 6th Scores row are GATED on persona-supplied
# (a guard phrase adjacent to each), so an unconditional 6th lens fails the test , not just present.
grep -qiE 'ONLY when a .?persona' commands/visual-team.md            # 6th lens guard
grep -qiE 'row appears ONLY when a .?persona' commands/visual-team.md # 6th Scores row guard
# NEGATIVE CONTROL: the 5 existing lenses are present UNCHANGED, and the no-arg path fires exactly 5:
for L in 'Hierarchy / typography' 'System-consistency' 'Accessibility / contrast' 'Restraint / simplicity' 'Expressiveness / brand-fit'; do
  grep -qF "$L" commands/visual-team.md || echo "MISSING LENS: $L"
done
grep -qiE 'exactly 5 lenses|exactly the 5|byte-identical' commands/visual-team.md   # no-arg = 5
# F2 ui-design PERSISTS (brief line) AND THREADS (forwards to visual-team $ARGUMENTS):
grep -qiE 'Persona' commands/ui-design.md
grep -qiE 'forward.*persona|persona:.*ARGUMENTS|persona: <archetype>' commands/ui-design.md
# DEC-017 (formal Decision Log) + SPEC-016 amendment pointer + kit-health carve-out:
grep -q 'DEC-017' docs/specs/SPEC-109-persona-lens.md
grep -q 'DEC-017' docs/specs/SPEC-016-critique-and-test-lanes.md
grep -qiE 'operator-supplied .?persona|sanctioned' commands/kit-health.md
bash tests/test-meta.sh   # green incl. the SPEC-109 persona block
```

## After state

- `commands/visual-team.md`: `$ARGUMENTS` persona parse, a conditional inline 6th lens, a
  conditional 6th Scores row; the 5 lenses + no-arg path byte-unchanged.
- `commands/ui-design.md`: seeds a `Persona:` line in the `## UI design` brief.
- `docs/specs/SPEC-109-persona-lens.md`: DEC-017 (the boundary vs DEC-003).
- `docs/specs/SPEC-016-critique-and-test-lanes.md`: DEC-003 gains a one-line amendment pointer to
  DEC-017 (explicit, not silent).
- `commands/kit-health.md`: check-13 carve-out for the sanctioned operator-persona lens.
- `tests/test-meta.sh`: a persona block , persona-arg + 6th-lens + conditional-Scores pins, the
  5-lenses-unchanged NC, the ui-design thread, the DEC + carve-out presence.
- `docs/verification/persona-lens.md`: the run-table incl. the 5-lens NC + kit-health carve-out.

## Open questions

The "6 lenses dispatch WITH persona / 5 byte-compatible WITHOUT" fixture is grep-based, not a
live command run: `/kit:visual-team` is a prompt (no shell dispatcher), the same SPEC-078 /
SPEC-107 fidelity. "Byte-compatible" is enforced structurally , the persona lens + 6th Scores row
are purely ADDITIVE and guarded by "if `persona:` supplied", and the test pins the 5 existing lens
lines present verbatim, so the no-arg output cannot drift. The DEC is the load-bearing artifact;
without it, kit-health and the next maintainer read this as re-opening a settled rejection.

## Decision Log

- **DEC-017 (2026-07-03): an operator-supplied runtime `persona:` archetype is SANCTIONED; it does
  NOT re-open DEC-003.** The boundary is **supplied-not-baked**, not archetype-vs-named-person:
  DEC-003 (SPEC-016) rejected personas the KIT SHIPS as its own lenses (Carmack/Rams baked in ,
  "off house-style, taste/maintenance liability" the kit would own). This lens is different on
  every axis that mattered to DEC-003: (1) the kit ships NO persona (nothing to maintain, no
  house-style claim); (2) it is operator-supplied per run, so the taste liability is the
  operator's, not the kit's; (3) it is critique-only (persona-shaped GENERATION stays a non-goal,
  SPEC-020; the brief's Tone/Differentiation fields own that); (4) it is an INLINE dispatch (no
  persona-NAMED agent file, so kit-health check-13's "agents named for personas" cannot fire on
  it). A runtime `persona: <a named person>` is therefore STILL on the operator's side of the
  boundary (supplied, not baked) , it does not re-open DEC-003. The 5 baked house-style lenses and
  the no-arg path are unchanged. SPEC-016 DEC-003 carries the reciprocal amendment pointer;
  kit-health check-13 carries the carve-out.
