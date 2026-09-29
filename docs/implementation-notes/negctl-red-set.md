# Implementation notes -- negctl-red-set

Deltas from SPEC-364. Nothing here repeats what the spec already states.

## 2026-09-29 Spec written, build not started
- Context: the spec is drafted and waits for parallel validation before any code changes.
- Open question for validation: the kit's own suites name the case in a section header (`echo "[N] ..."`) and put only detail in the FAIL line. The spec leaves that shape out of scope and has new cases carry the id in the FAIL line. If reviewers want header-aware labels, it is a scope change, not a fold.
- Build constraint carried from Grounding: five cases in `tests/test-proof-negctl.sh` resolve mutation lines by `grep -Fn ... | head -1`. The implementation must not add an earlier line containing any of those strings.

## 2026-09-29 Round 1 fold (NEEDS REVISION, 3 criticals)
- Folded all three criticals (fail-closed capture, FEATURES.md in Touches with an unconditional `--fix`, mismatch ranked last) and every warning into the spec.
- Deviation: the fold asked for `mktemp -t negctl-red.XXXXXX`. A live probe showed macOS `mktemp -t` ignores `TMPDIR`, so the unwritable-TMPDIR case and the under-root fallback could not be tested there. The spec uses the explicit `"${TMPDIR:-/tmp}/negctl-red.XXXXXX"` template that `--at` already uses (DEC-I).
- Fixture fix found while folding: the first draft's `add-0-0` label never goes red under `s/+/-/`, because 0-0 is 0. No fixture uses it now.
- Side effect of the probe: two empty `negctl-red.XXXXXX.*` files were left under the macOS per-user temp dir. They are harmless and were not deleted.
