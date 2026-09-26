# Implementation notes: SPEC-320 spec auto-validate

Delta from `docs/specs/SPEC-320-spec-autovalidate.md`. The spec's own decisions are not repeated here.

## Deviations and decisions

- The operator asked to "require" validation. The design critique showed the hard ship-gate on the normal lane lands estate-wide and reclassifies history, so the spec executes validation automatically at every entry point, blocks the build in `/kit:execute`, and keeps the normal-lane ship-gate cell `run-lite`. The flip to `measure-twice` stays one cell if the operator still wants it.
- The spec took four fresh validation passes (NEEDS REVISION 3 critical, 3 critical, 2 critical, then APPROVED). Each pass found real defects the author missed, including a preflight grep that would have matched a failed validation.
