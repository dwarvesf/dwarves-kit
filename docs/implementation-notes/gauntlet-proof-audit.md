# Implementation notes: gauntlet-proof-audit (delta from SPEC-242)

## 2026-09-01 the scrub axis is credential VALUE, not the op:// pointer

Context: SPEC-242's first draft contract said "no op:// string in committed evidence". The live acceptance run flagged 4 of 8 records for carrying the literal `op://Toolkit/anthropic-api-key` in their transcripts.
Decision: an `op://` reference is a POINTER, allowed by estate secret-handling policy (a path/reference is not a secret; the resolved value is). The scrub axis checks for a resolved credential VALUE (`sk-ant-`, an assigned key value) = DANGER; a bare `op://` pointer is not flagged.
Why: flagging pointers is a false-positive that would make every real run FLAG, drowning the one signal that matters (an actual key value). The estate rule is explicit: pointers stay allowed.
Impact: the corrected contract turns those 4 FLAGs into OK. The audit surfaced its own over-strict contract on its first run, which is the audit working.

## 2026-09-01 oldest record is UNTESTABLE on the checker axis

`2026-08-06-kit-user` (ROUNDS.md + J3-ROUNDS.md) predates the per-round `checker-output.txt` convention, so the "recorded verdict == checker-output" axis cannot be tested there. Correctly downgraded to UNSURE per the audit-loop hard rule (no-evidence verdict is UNSURE, never a fabricated OK), not treated as a defect.

## 2026-09-01 skill, not command

Per the spec: siblings (doc-drift, backlog-reconcile) are skills invoked as `/kit:<name>`; a skill needs a README Skills-table row + a FEATURES regen, but no architecture-inventory row (that counts commands + agents). Keeps the doc-projection surface untouched.
