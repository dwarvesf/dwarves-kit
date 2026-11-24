# Implementation notes -- shared-spec-merged

Delta from the spec, one section per half.

## Merged check

- Lead decisions folded into the spec first: no `--allow patch`, the patch-id check in `wrap-carry.sh` stays a named `merged-ok` exclusion, header-less specs are open everywhere.
- `tests/test-branch-merged-callers.sh` is self-contained (own gh shim, `mktemp -d` scratch, `url.<bare>.insteadOf` behind a GitHub URL) instead of using `tests/lib/wrap-stub.sh`: `wt.sh close` asks `pr list --state all --jq`, which the wrap stub does not model. The adopt rows went into `tests/test-wrap-adopt.sh` (case 31b), beside the existing merged-PR cases.
- TASK-3 moved `_origin_url`, `_gh_state` and `_gh_note` with the ladder, not only the ladder and its squash helpers: `branch_merged` calls all three, and `lib/goal/wt.sh` must source one file without the wrap library. `wrap-common.sh` sources the new file first, so every wrap verb still sees the same names.
- `tests/test-wrap-apply.sh` built `_absorbed` for its descriptor-exhaustion rows with `sed` over `lib/wrap/wrap.sh`, which holds no such function, so the extracted text was empty and the rows passed without running it. The extraction now reads `lib/gate/branch-merged.sh`.
- `tests/lib/wrap-stub.sh` `reword_ladder` rewords phrases in the moved file now.
- Added `--numbers` to `branch_merged` (not in the spec contract). `wrap adopt` prints the numbers of the merged PRs ("merged #7 #8") and tells an unreadable PR list from "no merged PR"; the verdict line carries neither. `--numbers` prints the numbers that match the tip under the same predicate (exit 0, 1 none, 2 unreadable), so adopt holds no copy of the predicate.
- `branch_merged` requests `number,headRefName,headRefOid,baseRefName,mergedAt,isCrossRepository` from gh and drops fork rows (DM6). A row without `headRefName` is accepted from `gh pr list --head` (gh already filtered by head) and refused from `--prs-json`.
- The origin sweep still reads one repo-wide merged list (one `gh` call, `merged-ok` marker on that line) and keeps its own guards: default branch, `--own`, an open PR using the branch as head or base, the lease. It pre-filters candidates by head name, then asks `branch_merged --need pr --tip <origin tip> --prs-json` for each. The `tests/test-wrap-apply.sh` fixture rows now carry `baseRefName` and `mergedAt`, as gh returns them for `--state merged`.
- `wrap-carry.sh`: the exact-tip check goes through `branch_merged --need pr --tip`; the `<branch>-squash` sibling probe and the two patch-id lines stay, each with a `merged-ok` marker and reason.
Delta from the spec.

## Active spec

- A spec with no `Status:` header is open everywhere, readiness included. `--none` is not an argument of `spec_active`; the function always calls `spec-status.sh live --none live`.
- `spec_active` always prints `<kind><TAB><path>`, default mode included. The spec also says default-mode output is byte-identical to `spec_for_slug`; the two statements cannot both hold. AC1 compares the path column.
- Readiness: a lone header-less spec now resolves (`spec:NONE`, no cycle suggestion); before, it printed "no spec found". `tests/test-spec-states.sh` pins the new line.
- Readiness: the exact-slug name pick now runs before the token match, so branch `feat/gate` with open `SPEC-001-gate` and `SPEC-002-gate-ext` resolves the first; before, both matched the token and it printed ambiguous. This follows from the name-first rule in the contract.
- Drift guard: the warning text lists spec paths relative to the cwd when the cwd is the repo root, absolute otherwise. Without `spec-active.sh` it resolves no spec and falls to `.gsd/`, else stays silent.
- `spec-index.sh` lists through `spec_files`: dot-dir copies, `node_modules`, `vendor`, `target`, `dist` and `build` trees disappear, and the walk stops 7 levels down.
- `tests/test-hooks.sh` live-filter rows: no-Status and empty specs are now open for readiness, so the three rows list SPEC-004 and SPEC-005.
