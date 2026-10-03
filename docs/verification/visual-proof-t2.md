# Verification -- visual-proof-t2

`proof-ledger.sh check` gains an opt-in image rule (R1 to R4): with
`proof.visual = true`, a behavioral diff that touches a UI file needs one
qualifying image (uploaded manifest entry, committed image, or local-mode cached
file) after all existing proof rules pass. With the flag off the gate is
byte-identical to before, and `classify` output is unchanged. Spec:
`docs/specs/SPEC-385-visual-proof-upgrade.md`, task T2.

Battery round 1 hardened the rule: manifest `slug`/`rand`/`file` are validated
before any path is joined, entry URLs holding `..` or `%` are refused, declared
bytes over 3 MB refuse before any fetch, verified fetches cap at five per check,
the default fetch adds `-q` against `~/.curlrc`, a committed image counts only
when the branch changed the image itself, the project `.kit.toml` is read only
when `kit_config_tracked_clean` holds, and an audited override clears a
visual-only block (never a source-code change) exactly like the proof block.

## Green run: the gate suite, cases 1 to 19

Command: `bash tests/test-proof-visual-gate.sh`
Exit: 0
Output (tail):
```
=== case 12: a non-UI code file alone is not visual ===
PASS case 12: app/models/user.rb only, text-only proof passes
=== case 13: an R3a url holding '..' or '%' is refused, prefix or not ===
PASS case 13a: '..' inside a bucket-prefixed url
PASS case 13a: the block names the unsafe url
PASS case 13b: '%' inside the url
PASS case 13b: the block names the unsafe url
=== case 14: declared bytes over the 3 MB cap is refused before any fetch ===
PASS case 14: over-cap entry refused with no fetch
=== case 15: at most 5 fetches per check ===
PASS case 15: fetch count capped at 5 (saw 5)
=== case 16: an old tracked image unchanged by the branch is not R3b ===
PASS case 16: a tracked image the branch did not change does not count
=== case 17: R3c refuses a traversal slug or file before the -f test ===
PASS case 17a: file '../escape.webp' must not resolve outside the cache
PASS case 17b: slug '..' must not resolve outside the cache
=== case 18: an uncommitted .kit.toml cannot disarm an operator opt-in ===
PASS case 18: an untracked .kit.toml cannot disarm the operator opt-in
PASS case 18b: a committed clean .kit.toml still disarms (auditable opt-out)
=== case 19: an audited override clears the visual block like the proof block ===
PASS case 19: no image, no override -> blocked
PASS case 19: a logged override clears the visual block
PASS case 19b: the override still rejects a source remainder (.tsx)

test-proof-visual-gate: all 31 passed
```
Verdict: PASS

## Green run: the existing proof and ship-gate suites, R1 off

Command: `bash tests/run-all.sh --changed origin/master` (55 suites; recap below)
Exit: 1 (test-meta only; see the caveat at the bottom)
Output (tail):
```
  tests/test-proof-captured-output                     ok
  tests/test-proof-dir-layout                          ok
  tests/test-proof-experiment-verification-path        ok
  tests/test-proof-negctl                              ok
  tests/test-proof-override-order                      ok
  tests/test-proof-tool-verification-path              ok
  tests/test-proof-verdict-hint                        ok
  tests/test-proof-visual-evidence                     ok
  tests/test-proof-visual-gate                         ok
  tests/test-ship-gate-coverage-map                    ok
  tests/test-ship-gate-fail-closed                     ok
  tests/test-ship-gate-profiles                        ok
  tests/test-ship-pr-body-verified                     ok
```
Every proof and ship-gate suite that ran green before this change still runs
green, which is the R1-off byte-identical contract. `test-meta` fails one pin,
`docs/FEATURES.md is fresh`: the generated projection counts token references
and this branch's spec prose plus the new test file's `docs/verification`
strings each add one reference. Regenerating `docs/FEATURES.md` is outside the
T2 file set, so it is left for the landing pass (`feature-registry.sh check
--fix`), which the ship-gate already forces pre-push. One more drifted row,
`/kit:start`, is stale on `origin/master` itself, verified in a temp copy of
the base commit.
Verdict: PASS

## Negative control

The new test file overlaid on a temp copy of `origin/master` (master's
`lib/gate/proof-ledger.sh` and `kit.toml`, no worktree files modified). Every
case that expects the new gate to block a missing or bad image must go red
because master's gate has no image rule at all.

Command: `git archive origin/master | tar -x -C <tmp>; cp tests/test-proof-visual-gate.sh <tmp>/tests/; bash <tmp>/tests/test-proof-visual-gate.sh`
Exit: 1
Output (tail):
```
=== case 14: declared bytes over the 3 MB cap is refused before any fetch ===
FAIL case 14: over-cap entry (ACCEPTED, want BLOCK)
=== case 15: at most 5 fetches per check ===
FAIL case 15: seven unverifiable entries (ACCEPTED, want BLOCK)
=== case 16: an old tracked image unchanged by the branch is not R3b ===
FAIL case 16: a tracked image the branch did not change does not count (ACCEPTED, want BLOCK)
=== case 17: R3c refuses a traversal slug or file before the -f test ===
FAIL case 17a: file '../escape.webp' must not resolve outside the cache (ACCEPTED, want BLOCK)
FAIL case 17b: slug '..' must not resolve outside the cache (ACCEPTED, want BLOCK)
=== case 18: an uncommitted .kit.toml cannot disarm an operator opt-in ===
FAIL case 18: an untracked .kit.toml disarmed the operator's visual = true
PASS case 18b: a committed clean .kit.toml still disarms (auditable opt-out)
=== case 19: an audited override clears the visual block like the proof block ===
FAIL case 19: no image, no override -> blocked (ACCEPTED, want BLOCK)
PASS case 19: a logged override clears the visual block
FAIL case 19b: the override still rejects a source remainder (.tsx) (ACCEPTED, want BLOCK)

test-proof-visual-gate: 23 FAILED of 31
```
Result: RED as expected. 23 assertions fail on master (every block-expecting
check across cases 2, 4, 5, 9, 10, 11, 13-17, 18, and 19) because master's gate
never refuses a visual diff and validates nothing inside the manifest or its
URLs; the accept-expecting cases still pass because a gate with no image rule
accepts everything, including case 19's "a logged override clears the visual
block" (with no visual rule there is nothing to clear).

Verdict: PASS
