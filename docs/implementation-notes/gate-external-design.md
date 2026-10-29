# Implementation notes: gate-external-design

Delta from `docs/specs/SPEC-414-gate-external-design.md`. Decisions already in the spec are cited, not repeated.

## Decisions not in the spec

- The branch was renamed from the Orca default `tieubao/gate-external-design` to `feat/gate-external-design`. The slug, and so the rid, stays `gate-external-design`.
- The fold after validation round 1 went straight to a full re-validation round. The fold-diff check was skipped because the full round re-runs both lenses the fold touched (Reviewers 2 and 4) with the diff as context.

## Validation round 1 warnings, resolved in the build

- `_ext_verify` calls `_ext_parse` first and builds the API path only from the parsed parts. A hand-appended cite line with `?`, `&` or `..` fails with no `gh` call. (Reviewers 1, 2, 5.)
- The 2-citation cap is deterministic: newest cite line first. A ledger with more prints one `EXTERNAL-DESIGN:` line saying how many were not tried. (Reviewers 3, 4, 5, 6.)
- `gh` output goes to a temp file and the wrapper kills by PID, so a stub's grandchild cannot hold a capture pipe open past the bound. (Reviewers 2, 3.)
- The `EXTERNAL-DESIGN:` reason strips control characters and is cut at 160 characters. (Reviewer 1.)
- A test pins the covered set to the six names, so a later addition to `INHERITABLE` cannot widen it silently. (Reviewer 3.)
- A test greps `hooks/ship-gate.sh`, `lib/gate/ship-rules.sh` and `lib/goal/mega-merge.sh` for `--offline` and wants zero hits. (Reviewer 1.)
- `proof-table-gen.py` and the `plan-record` / `record-batch` echo of `check` are display readers: they pass `--offline`. (Reviewers 3, 5.)

## Validation round 1 warnings, not taken

- Count a cite line as an override in the waiver counters (lane-telemetry, ceremony stats). Reviewers 1 and 4 asked for it. It is a stats change in two readers with their own tests. Left for Han's call on the PR, together with DEC-2 and DEC-6.
- Make `GH_CMD` test-only. Any environment switch is equally reachable, and the ledger is agent-writable (spec threat model). Kept, matching `orchestrate.sh`.
- Non-ASCII design-doc paths are refused (exit 64). The override fallback covers them. Named here; the grammar stays ASCII.
