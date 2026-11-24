# Implementation notes -- shared-spec-merged

Delta from the spec.

## Active spec

- A spec with no `Status:` header is open everywhere, readiness included. `--none` is not an argument of `spec_active`; the function always calls `spec-status.sh live --none live`.
- `spec_active` always prints `<kind><TAB><path>`, default mode included. The spec also says default-mode output is byte-identical to `spec_for_slug`; the two statements cannot both hold. AC1 compares the path column.
