# Implementation notes -- shared-spec-merged

Delta from the spec, one section per half.

## Merged check

- Lead decisions folded into the spec first: no `--allow patch`, the patch-id check in `wrap-carry.sh` stays a named `merged-ok` exclusion, header-less specs are open everywhere.
- `tests/test-branch-merged-callers.sh` is self-contained (own gh shim, `mktemp -d` scratch, `url.<bare>.insteadOf` behind a GitHub URL) instead of using `tests/lib/wrap-stub.sh`: `wt.sh close` asks `pr list --state all --jq`, which the wrap stub does not model. The adopt rows went into `tests/test-wrap-adopt.sh` (case 31b), beside the existing merged-PR cases.
