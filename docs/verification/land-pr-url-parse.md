# Verification -- land-pr-url-parse

`wrap land`, the `wrap merge` squash fallback and the `wrap apply` autoland carry read the new PR's number from the last `gh pr create` output line that is a GitHub PR URL, so the hint block newer gh prints after the URL no longer makes them refuse.

| Claim | Evidence |
|---|---|
| A PR URL followed by a hint block lands (land, squash fallback, carry) | Green run, the `hint after the URL` cases |
| A hint block with no URL still refuses and merges nothing | Green run, the `hint only` cases |
| The new cases depend on the fix | Negative control |
| No other suite regressed | Green run, `run-all.sh --changed` |

## Green run

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
run-all: --changed against 04640338: 8 changed files -> 35 suites (27 named, the rest always-on)
test-wrap-carry                                ok (58s)
test-wrap-land                                 ok (148s)
test-wrap-merge                                ok (82s)
run-all: all 35 suites passed, 0 skipped for missing tooling

Command: LAND_CACHE=0 LAND_ONLY=happy bash tests/test-wrap-land.sh
--- gh prints a hint block after the PR URL: the number still comes from the URL line
  PASS hint after the URL: land exits 0
  PASS hint after the URL: land reports the PR number
  PASS hint after the URL: no refusal
  PASS hint after the URL: land merged #45
--- gh prints only the hint block, no URL: land still refuses and merges nothing
  PASS hint only: land exits 2
  PASS hint only: land names the missing PR number
  PASS hint only: land never merges
test-wrap-land: all 48 passed

Command: bash tests/test-wrap-merge.sh
  PASS hint after the URL: the squash fallback exits 0
  PASS hint after the URL: the replacement PR is #61
  PASS hint after the URL: no refusal
  PASS hint after the URL: #61 merged
  PASS hint only: the fallback names the missing PR number
  PASS hint only: the fallback merged nothing
test-wrap-merge: all 286 passed

Command: bash tests/test-wrap-carry.sh
  PASS autoland hint after the URL: apply exits 0
  PASS autoland hint after the URL: the PR number is read from the URL
  PASS autoland hint after the URL: the merge verifies
  PASS autoland hint after the URL: nothing failed
  PASS autoland hint only: the failure names gh pr create
  PASS autoland hint only: no merge ran
test-wrap-carry: all 151 passed
Verdict: PASS
```

The gh stub (`tests/lib/wrap-stub.sh`) gained `GH_STUB_CREATE_HINT=after|only`: `after` prints the URL then a multi-line `hint: ... gh event listen ...` block, `only` prints the block with no URL.

## Negative control

```
Command: bash lib/gate/negctl.sh --at <sha of the change> "$PWD" "<suite>" "perl -pi -e 's/_pr_url_from_create \"\$created\"/printf \"%s\\n\" \"\$created\" | tail -1/' lib/wrap/wrap-land.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-carry.sh"
Exit: 1 under the mutation, 0 after restore
Output:
Changed: lib/wrap/wrap-carry.sh, lib/wrap/wrap-land.sh, lib/wrap/wrap-merge.sh
suite tests/test-wrap-carry.sh
  Exit: 1 (under mutation, RED expected)
  FAIL autoland hint after the URL: apply exits 0
  FAIL autoland hint after the URL: the PR number is read from the URL
  FAIL autoland hint after the URL: the merge verifies
  FAIL autoland hint after the URL: nothing failed
  test-wrap-carry: 147 passed, 4 FAILED of 151
suite tests/test-wrap-merge.sh
  Exit: 1 (under mutation, RED expected)
  test-wrap-merge: 283 passed, 3 FAILED of 286
suite LAND_ONLY=happy tests/test-wrap-land.sh
  Exit: 1 (under mutation, RED expected)
  FAIL hint after the URL: no refusal
  FAIL hint after the URL: land merged #45
  test-wrap-land: 44 passed, 4 FAILED of 48
Restore: git checkout HEAD -- lib/wrap/wrap-carry.sh lib/wrap/wrap-land.sh lib/wrap/wrap-merge.sh
Exit: 0 (green after restore), all three suites
Verdict: PASS
```

The mutation put the old `tail -1` read back at all three sites. The `hint after the URL` cases went red in each suite; the `hint only` cases stay green on both sides, as they should: the old code and the new code both refuse a URL-less output. The restore turned each suite green again.

## Not proven

- Real gh. Every run used the stub, shaped on the hint block observed from the installed gh; no PR was opened on GitHub.
- A PR URL that gh prints on a line with other text before it. The parse needs the URL alone on its line (trailing whitespace allowed), which is what gh prints.
- The installed copy. This proof ran in the worktree; the installed kit picks the fix up on its next update.
