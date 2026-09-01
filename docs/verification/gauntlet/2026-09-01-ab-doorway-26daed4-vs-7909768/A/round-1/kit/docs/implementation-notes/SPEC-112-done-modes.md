# Implementation notes: SPEC-112 done-modes

Delta from the spec. References, does not restate.

## 2026-07-03 spec-validate: CHANGES-REQUIRED, 2 HIGH + 4 minor folded

- **F1 (HIGH):** the goal's crux proof (the fixture traces) was promised in After-state but not
  pinned in the executable Verification. Fix: `docs/verification/done-modes.md` carries 4 worked
  traces (converge / cap-out / no-false-quiescence / plain-REVISE regression) and test-meta greps
  them, so the proof cannot pass on contract text alone.
- **F2 (HIGH):** `### Deferred findings` authorship was undefined and collided with two live rules
  (ui-design Step 3 says the loop must NOT write `## Visual critique`; visual-team REWRITES it each
  round + is stateless). Resolved: the ui-design LOOP LEAD appends `### Deferred findings` to the
  FINAL `## Visual critique` AFTER the loop terminates , an explicit carve-out, so round N+1's
  rewrite cannot eat it. Pinned in ui-design.md + the spec + the proof.
- **F3 (MEDIUM):** the two-sided-stop grep had an escape hatch (`|no OPEN .*HIGH` passed a one-sided
  condition). Removed , the pin now requires the full `zero NEW >=HIGH AND no OPEN >=HIGH`
  conjunction. (Also: the stop-condition text had wrapped across two lines, defeating the
  line-based grep; put it on one line.)
- **F4 (MEDIUM):** ">=HIGH is one notch stricter" was inverted. Reworded: the BLOCKING threshold is
  one notch HIGHER (HIGH vs test-plan-review-team's MEDIUM); MEDIUM/LOW DEFER, not block.
- **F5 (NIT):** noted why the strictly-falling-findings guard is NOT adopted (the two-sided severity
  stop + hard cap 3 bound the loop; resolving a CRITICAL while surfacing a MEDIUM is progress).
- **F6 (NIT):** the dotfiles `Done-mode:` field is marked UI-ONLY / OMIT-for-non-UI (like the
  Persona line); the 06 persona dependency is closed explicitly (each quiescence round re-runs Step
  3, which threads the brief's Persona line).

## Notes

- The quiescence loop is prose (ui-design has no shell dispatcher; not in CI, downstream-facing), so
  the fixtures are worked round-sequence TRACES, and the load-bearing NC (a re-found CRITICAL does
  not quiesce) is pinned structurally via the two-sided-conjunction grep + the trap statement.
- Dotfiles half committed atomically: dotfiles `ac2c6a4`.
