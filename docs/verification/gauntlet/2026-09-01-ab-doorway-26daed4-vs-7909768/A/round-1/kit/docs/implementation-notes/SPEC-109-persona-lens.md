# Implementation notes: SPEC-109 persona-lens

Delta from the spec. References, does not restate.

## 2026-07-03 spec-validate: VALIDATED-WITH-NITS, 5 findings folded

Governance crux (DEC-003 boundary) HELD as principled , the axis is supplied-not-baked, not
archetype-vs-named-person. Tightenings applied:

- **F1 (HIGH, conditionality):** pinning the 5 lens lines present did NOT prevent an unconditional
  6th lens (a future edit could break byte-compat and still pass). Fix: both the 6th lens and the
  6th Scores row carry an explicit "ONLY when a `persona:` ... supplied" guard phrase, and
  test-meta pins those guards (`ONLY when a .?persona`, `row appears ONLY when a .?persona`). Now
  an unconditional 6th lens FAILS the test.
- **F2 (MEDIUM, thread not just persist):** the goal's "ui-design threads it" needs the lens to
  FIRE from the ui-design path, not merely be stored in the brief. Fix: ui-design Step 3 now
  FORWARDS a non-blank brief `Persona:` line into `/kit:visual-team`'s `$ARGUMENTS` (in addition
  to seeding the brief); test-meta pins both the persist (brief line) and the thread (forward).
- **F3 (LOW, formal DEC):** DEC-017 is now a formal `## Decision Log` block (matching SPEC-016's
  format), stating the boundary as supplied-not-baked explicitly, so a runtime `persona: <a named
  person>` is understood to stay on the operator's side (not a DEC-003 re-opening).
- **F4 (LOW, contradiction):** visual-team's Source line ("no named-person personas") reconciled to
  "no BAKED named-person personas; operator-supplied rides an opt-in inline 6th lens, DEC-017".
- **F5 (NIT, arg parse):** the persona parse note states `persona:` is parsed by its literal prefix,
  disjoint from the visual-source input, so the two do not collide.

## Notes

- The "6 lenses dispatch / 5 byte-compat" proof is grep-based (visual-team is a prose command with
  no shell dispatcher , SPEC-016 known-limitation 5, same SPEC-078/107 fidelity). Byte-compat is
  enforced STRUCTURALLY: the 5 lens lines are pinned verbatim + the 6th lens/row are guarded, so the
  no-arg path cannot drift.
- kit-health check-13 is a human-judgment REJECT item (no automated grep); the carve-out defends the
  human-review reading. Proven by the carve-out text being present, not by a live kit-health run
  (kit-health is a prose command).
