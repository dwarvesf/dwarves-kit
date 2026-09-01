# Implementation notes: gauntlet-proof-audit (delta from SPEC-242)

## 2026-09-01 the scrub axis is credential VALUE, not the op:// pointer

Context: SPEC-242's first draft contract said "no op:// string in committed evidence". The live acceptance run flagged 4 of 8 records for carrying the literal `op://Toolkit/anthropic-api-key` in their transcripts.
Decision: an `op://` reference is a POINTER, allowed by estate secret-handling policy (a path/reference is not a secret; the resolved value is). The scrub axis checks for a resolved credential VALUE (`sk-ant-`, an assigned key value) = DANGER; a bare `op://` pointer is not flagged.
Why: flagging pointers is a false-positive that would make every real run FLAG, drowning the one signal that matters (an actual key value). The estate rule is explicit: pointers stay allowed.
Impact: the corrected contract turns those 4 FLAGs into OK. The audit surfaced its own over-strict contract on its first run, which is the audit working.

## 2026-09-01 oldest record is UNTESTABLE on the checker axis

`2026-08-06-kit-user` (ROUNDS.md + J3-ROUNDS.md) predates the per-round `checker-output.txt` convention, so the "recorded verdict == checker-output" axis cannot be tested there. Correctly downgraded to UNSURE per the audit-loop hard rule (no-evidence verdict is UNSURE, never a fabricated OK), not treated as a defect.

## 2026-09-01 battery deltas

Four-leg battery (acceptance/review/advisor; security lens skipped by decision, read-only audit skill, no subprocess/secret/network surface). Fixes folded:
- Review LOW-MED: Tier-1 now cross-checks the marker's own `clean=` against the checker verdict, not only the table cell (a marker could disagree while the cell agrees).
- Review LOW: stale "no op:// string" wording in the spec Picture bullet corrected to match the four-slots table; audit-loop.md gained a Known-instances paragraph (not just the SDLC-table row).
- Review LOW nit: the scrub shape widened past Anthropic-only to any recognizable token (`sk-ant-`, `sk-`, `ghp_`, an assigned 20+-char opaque value).
- Advisor: marker grammar now DELEGATES to `bash lib/gauntlet/stats.sh` (its Pass-1 sweep is the single enforcer) instead of restating the regex, so it cannot desync; added `tests/test-gauntlet-proof-audit.sh` (extracts the item-set command from the SKILL and runs the verdict/scrub rules against fixtures) so the AC-3 control is a re-runnable regression, wired into FEATURES and CI; flipped SPEC status VALIDATED + board shipped.
- Advisor accept-by-design (operator owns): report-first means a FLAG can sit un-acted-on; cadence stays on-demand (no schedule shipped); FLAG never auto-corrects (a dated note lands only on DANGER).

## 2026-09-01 skill, not command

Per the spec: siblings (doc-drift, backlog-reconcile) are skills invoked as `/kit:<name>`; a skill needs a README Skills-table row + a FEATURES regen, but no architecture-inventory row (that counts commands + agents). Keeps the doc-projection surface untouched.
