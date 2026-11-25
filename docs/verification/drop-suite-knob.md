# Verification: drop-suite-knob

Deletes the dead `[test] suite` line in `kit.toml` and the `suite` verb of `lib/gate/known-failures.sh`; nothing read them after the affected-only work loop. Also turns `tests/test-known-failures.sh` C1 green on master (it asserted the deletion before it landed). Full-lane gates logged as audited overrides on the owner's order.

## Green run
```
Command: bash tests/test-known-failures.sh
Exit: 0
Output:
PASS C5: without failure_line at the base a red run is a plain failure
---
All known-failures tests passed.
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 1 (runner), 45 suites run
Output:
test-known-failures                            ok (3s)
run-all: FAILED -> test-proof-capture-route
run-all: 45 suites run, 0 skipped for missing tooling
Verdict: PASS for this change; test-proof-capture-route fails on its mktemp cases, owned by a parallel fix branch, untouched here.
```

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-known-failures.sh" "git checkout HEAD~1 -- lib/gate/known-failures.sh"
Exit: 0 (green before mutation), 2 (under mutation, RED expected), 0 (green after restore)
Output:
FAIL C1: lib/gate/known-failures.sh still reads a full-suite knob
FAIL C1: known-failures.sh still answers suite
Verdict: PASS
```
Restoring the suite verb turns C1 red; negctl restored the file.

## Not proven
- A consumer `.kit.toml` that still sets `[test] suite` is ignored, not reported.
