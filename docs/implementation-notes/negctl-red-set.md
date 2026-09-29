# Implementation notes -- negctl-red-set

Deltas from SPEC-364. Nothing here repeats what the spec already states.

## 2026-09-29 Spec written, build not started
- Context: the spec is drafted and waits for parallel validation before any code changes.
- Open question for validation: the kit's own suites name the case in a section header (`echo "[N] ..."`) and put only detail in the FAIL line. The spec leaves that shape out of scope and has new cases carry the id in the FAIL line. If reviewers want header-aware labels, it is a scope change, not a fold.
- Build constraint carried from Grounding: five cases in `tests/test-proof-negctl.sh` resolve mutation lines by `grep -Fn ... | head -1`. The implementation must not add an earlier line containing any of those strings.
