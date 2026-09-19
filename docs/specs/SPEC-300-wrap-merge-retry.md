# SPEC-300: wrap merge retries transient GitHub failures

**Status:** VALIDATED (the change lands in the same PR)
Lane: full
**Board:** ID-881. **Proof:** `tests/test-wrap.sh`, the SPEC-300 block.

## Problem

`wrap.sh merge --apply` calls `gh pr merge` exactly once. Any transient GitHub
failure — an HTTP 502/503/504, a GraphQL `error executing query`, a TLS or
socket stall — fails the run even though the merge would land seconds later.
During a ~90-minute GitHub outage on 2026-09-13/14 the operator hand-rolled
three shell retry loops over ~25 PR merges (memory note
`hand-rolled-merge-loop-instead-of-wrap-merge.md`, second occurrence). The
missing piece is a bounded retry inside the verb, not an outside loop.

## Contract

- `gh pr merge` is wrapped by `_gh_merge_retry <n> <url> <head_oid>`. Both
  merge call sites (`cmd_merge`'s eligible merge and `land`'s merge) go
  through it.
- The helper retries **only** a failure whose output reads transient:
  `HTTP 5xx`, `429`, `error executing query`, a timeout, a reset, a TLS
  handshake error, `EOF`, `temporary`/`unavailable`. Matching is
  case-insensitive.
- A failure that does not match returns immediately with the original exit
  code and the captured output on stderr — "not mergeable", "draft",
  "Merge conflict", a `--match-head-commit` mismatch, a 401/403 are all real
  refusals and are never retried.
- Bound: at most `WRAP_MERGE_RETRY_MAX` (default 3) attempts, sleeping
  `attempt * WRAP_MERGE_RETRY_SLEEP` (default 5s) between them — a bounded
  ~15s window, enough for a blip, never an outage.
- Every retry prints `merge #<n>: transient GitHub error (attempt k/max),
  retrying in Xs` to stderr so the operator sees the wait.

## Design record

The retry lives inside the verb, not the caller, because both call sites need
the same semantics and an outside loop cannot tell a 502 from a 405. Matching
on the error text rather than the exit code is required: gh exits 1 for a
transient 502 and for a permanent "not mergeable" alike. The refusal class
must keep failing immediately — `--match-head-commit` mismatch in particular
is the guard against shipping an unreviewed push, and retrying it would only
ever merge the same wrong tree or fail again.

## Test plan

| Case | Stub behaviour | Expected |
|---|---|---|
| Merge succeeds first try | `GH_STUB_MERGE_RC=0` | one merge call, exit 0 |
| Transient 502 twice then OK | `GH_STUB_MERGE_FAILS=2`, error `HTTP 502` | three merge calls, exit 0 |
| Transient exhausts the bound | `GH_STUB_MERGE_FAILS=9`, error `HTTP 503` | exactly max calls, exit 2 |
| Real refusal | merge fails with `405 Method Not Allowed` | one merge call, exit 2, no retry line |
| match-head mismatch | merge fails with `head commit oid doesn't match` | one call, exit 2, no retry |
