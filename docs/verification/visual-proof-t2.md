# Verification -- visual-proof-t2

`proof-ledger.sh check` gains an opt-in image rule (R1 to R4): with
`proof.visual = true`, a behavioral diff that touches a UI file needs one
qualifying image (uploaded manifest entry, committed image, or local-mode cached
file) after all existing proof rules pass. With the flag off the gate is
byte-identical to before, and `classify` output is unchanged. Spec:
`docs/specs/SPEC-385-visual-proof-upgrade.md`, task T2.

## Green run: the new gate suite, cases 1 to 12

Command: `bash tests/test-proof-visual-gate.sh`
Exit: 0
Output (tail):
```
PASS case 4: the block names 'hash mismatch: <url>'
=== case 5: pending entry + fetch fails -> 'fetch failed' AND 'bin/proof-asset flush' ===
PASS case 5: pending entry whose fetch fails
PASS case 5: the block names 'fetch failed: <url>'
PASS case 5: the block says to run 'bin/proof-asset flush'
=== case 6: assets=local from a tracked, clean .kit.toml + cached file -> passes ===
PASS case 6: local asset with cached file passes
=== case 7: a committed (ls-files-listed) image linked in the proof -> passes ===
PASS case 7: tracked image embed passes
=== case 8: stateful diff touching a UI file gets no image rule ===
PASS case 8: stateful + UI file, text-only proof passes
=== case 9: assets=local only in an UNCOMMITTED .kit.toml -> R3c refused ===
PASS case 9: untracked .kit.toml cannot unlock the local path
=== case 10: entry url outside <base>/<owner>/<repo>/ -> named so ===
PASS case 10: url outside the proof bucket
PASS case 10: the block names 'url outside the proof bucket: <url>'
=== case 11: image link to a gitignored file under .kit/proof-assets/ is not R3b ===
PASS case 11: a gitignored target does not count
=== case 12: a non-UI code file alone is not visual ===
PASS case 12: app/models/user.rb only, text-only proof passes

test-proof-visual-gate: all 17 passed
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
=== case 9: assets=local only in an UNCOMMITTED .kit.toml -> R3c refused ===
FAIL case 9: untracked .kit.toml cannot unlock the local path (ACCEPTED, want BLOCK)
=== case 10: entry url outside <base>/<owner>/<repo>/ -> named so ===
FAIL case 10: url outside the proof bucket (ACCEPTED, want BLOCK)
FAIL case 10: the block names 'url outside the proof bucket: <url>' (missing 'url outside the proof bucket: https://proof.han.ws/tieubao/other/ui/0123456789abcdef0123456789abcdef/shot.webp' in: )
=== case 11: image link to a gitignored file under .kit/proof-assets/ is not R3b ===
FAIL case 11: a gitignored target does not count (ACCEPTED, want BLOCK)
=== case 12: a non-UI code file alone is not visual ===
PASS case 12: app/models/user.rb only, text-only proof passes

test-proof-visual-gate: 11 FAILED of 17
```
Result: RED as expected. All 11 block-expecting assertions fail on master
(cases 2, 4, 5, 9, 10, 11 including the 'no image', 'hash mismatch',
'fetch failed', 'flush', and 'outside the proof bucket' message pins) because
master's gate never refuses a visual diff; the six accept-expecting cases still
pass because a gate with no image rule accepts everything.

Verdict: PASS
