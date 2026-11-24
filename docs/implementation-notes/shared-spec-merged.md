# Implementation notes -- shared-spec-merged

Delta from the spec.

## Active spec

- A spec with no `Status:` header is open everywhere, readiness included. `--none` is not an argument of `spec_active`; the function always calls `spec-status.sh live --none live`.
- `spec_active` always prints `<kind><TAB><path>`, default mode included. The spec also says default-mode output is byte-identical to `spec_for_slug`; the two statements cannot both hold. AC1 compares the path column.
- Readiness: a lone header-less spec now resolves (`spec:NONE`, no cycle suggestion); before, it printed "no spec found". `tests/test-spec-states.sh` pins the new line.
- Readiness: the exact-slug name pick now runs before the token match, so branch `feat/gate` with open `SPEC-001-gate` and `SPEC-002-gate-ext` resolves the first; before, both matched the token and it printed ambiguous. This follows from the name-first rule in the contract.
- Drift guard: the warning text lists spec paths relative to the cwd when the cwd is the repo root, absolute otherwise. Without `spec-active.sh` it resolves no spec and falls to `.gsd/`, else stays silent.
- `spec-index.sh` lists through `spec_files`: dot-dir copies, `node_modules`, `vendor`, `target`, `dist` and `build` trees disappear, and the walk stops 7 levels down.
- `tests/test-hooks.sh` live-filter rows: no-Status and empty specs are now open for readiness, so the three rows list SPEC-004 and SPEC-005.
