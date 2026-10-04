# Implementation notes -- negctl-hint

Delta from `docs/specs/SPEC-315-negctl-hint.md` only.

- No deviation. Both hint strings (`proof_requirement`'s behavioral case at line 86, and
  `proof_contract`'s no-registry-row fallback at line 115) were edited exactly as the
  contract describes, each staying one line.
- Confirmed the `stateful` and `inert` cases of `proof_requirement()` do not ask for a
  negative control today, so the spec's "left alone" claim holds; no other hint needed the
  pointer.
- Confirmed no test pins the full hint sentence (only substring `assert_output_contains`
  checks against `rollback` / `negative control` / `exempt`), so only one new assertion was
  needed in `tests/test-hooks.sh`, no other test file changed.
- `proof_contract()`'s fallback branch (line 115) is effectively unreachable in current
  practice: `task-type-classify.sh classify` always resolves to a known type (falls back to
  `spec-feature`, which has a registry row), so the `(no registry row ...)` string never
  prints today. Fixed anyway per the task's explicit instruction to cover it, and it is live
  code, not dead code, if a new task type is ever added ahead of its registry row.
