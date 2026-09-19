# Proof of done: wrap merge retries transient GitHub failures

## What changed

`bin/wrap merge --apply` called `gh pr merge` exactly once, so any transient
GitHub failure (HTTP 5xx, a GraphQL "error executing query", a timeout or
reset) failed the run even though the merge would land seconds later. During
the ~90-minute GitHub outage on 2026-09-13/14 the operator hand-rolled shell
retry loops over ~25 PR merges.

`lib/wrap/wrap.sh` now routes both merge call sites (`cmd_merge`'s eligible
merge and `land`'s merge) through `_gh_merge_retry <n> <url> <head-oid>`: at
most `WRAP_MERGE_RETRY_MAX` (default 3) attempts with
`attempt * WRAP_MERGE_RETRY_SLEEP` (default 5s) linear backoff, a ~15s worst
window. `_gh_merge_transient` whitelists the failure text an outage prints
(HTTP 500/502/503/504/507/509/429, bad gateway, service unavailable, a GraphQL
"executing query", went wrong, rate limit, timeout, reset, TLS, EOF,
temporary, failed to connect). Any other failure returns on the first call
with its original output and exit code, so not-mergeable, draft, conflict, a
`--match-head-commit` mismatch and auth errors are never retried. A retry
answered "already merged" counts as the success it is; the post-merge `state
== MERGED` check and tree-verify still run unchanged. The row is ID-881, the
spec SPEC-300.

## Gate table

| Claim | Evidence |
|---|---|
| a transient 502 retries and the merge lands, tree verified | SPEC-300 block, run table below |
| a transient that outlasts the bound exits 2 after exactly 3 calls | SPEC-300 block, run table below |
| a 405 refusal and a match-head mismatch are never retried | SPEC-300 block, run table below |
| the whole suite still holds | run table below |
| the retry helper is load-bearing | negative control below |

## Run table

```
Command: bash tests/test-wrap.sh
Exit: 0
test-wrap: all 668 passed (12 SPEC-300 checks inside)
Verdict: PASS
```

```
Command: bash tests/test-meta.sh
Exit: 0
Passed: 853 / 853 (after docs/FEATURES.md regeneration)
Verdict: PASS
```

`docs/FEATURES.md` is a generated projection and was regenerated in the same
commit (`bash lib/registry/feature-registry.sh check --fix docs/FEATURES.md`),
which is what test-meta's freshness pin checks.

## Negative control (negctl)

```
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' 's|  _gh_merge_retry "\$first_eligible" "\$url" "\$head_oid"|  gh pr merge "$first_eligible" --repo "$url" --squash --match-head-commit "$head_oid"|' lib/wrap/wrap.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation puts the bare single-shot `gh pr merge` back at the cmd_merge
call site; five SPEC-300 checks go red (the transient-then-OK case loses its
merge and its retry line, and the bound case stops at one call).

## Test plan coverage

| Spec row | Run |
|---|---|
| merge succeeds first try | existing `merge --apply called pr merge exactly once` check |
| transient 502 twice then OK | `SPEC-300: a transient 502 retries and merges` + 3-call + retry-line + tree-verify checks |
| transient exhausts the bound | `SPEC-300: a transient that outlasts the bound exits 2` + bound-held + last-failure checks |
| real refusal (405) | `SPEC-300: a real refusal exits 2` + not-retried + no-retry-line checks |
| match-head mismatch | `SPEC-300: a match-head mismatch exits 2` + not-retried check |

## Rollback

`git revert` the feature commit. Both call sites return to single-shot
`gh pr merge`; no state, schema or flag was added that needs cleanup.
