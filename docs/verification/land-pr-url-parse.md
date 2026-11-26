# Verification -- land-pr-url-parse

`wrap land`, the `wrap merge` squash fallback and the `wrap apply` autoland carry read the new PR's number through one helper, `_pr_url_from_create` (`lib/wrap/wrap-common.sh`): the last `gh pr create` output line that is a GitHub PR URL on its own. Master already reads the URL line with an inline `grep -E '/pull/[0-9]+$' | tail -1` at each of the three sites and has no test for it. This change replaces the three copies with the helper and adds the tests, with the gh stub printing the hint block gh 2.105.0 prints.

| Claim | Evidence |
|---|---|
| A PR URL followed by a hint block lands (land, squash fallback, carry) | Green run, the `hint after the URL` cases |
| A hint block with no URL line refuses and merges nothing, even though its `gh event listen` line carries the PR URL mid-line | Green run, the `hint only` cases |
| The `hint after the URL` cases depend on reading the URL line | Negative control 1 |
| The `hint only` cases depend on the URL being a whole line | Negative control 2 |
| No other suite regressed | Green run, `run-all.sh --changed` |
| `\|\| true` at the three call sites changes no behaviour | The last run under "Not proven": the suites stay green without it |

## Green run

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
run-all: --changed against 498e3f0c: 10 changed files -> 39 suites (32 named, the rest always-on)
test-wrap-carry                                ok (41s)
test-wrap-land                                 ok (131s)
test-wrap-merge                                ok (77s)
run-all: all 39 suites passed, 0 skipped for missing tooling

Command: LAND_CACHE=0 bash tests/test-wrap-land.sh
--- gh prints a hint block after the PR URL: the number still comes from the URL line
  PASS hint after the URL: land exits 0
  PASS hint after the URL: land reports the PR number
  PASS hint after the URL: no refusal
  PASS hint after the URL: land merged #45
--- gh prints only the hint block, its PR URL mid-line and no URL line: land still refuses and merges nothing
  PASS hint only: land exits 2
  PASS hint only: land names the missing PR number
  PASS hint only: the output did carry the PR URL mid-line
  PASS hint only: the mid-line URL is not taken as the PR
  PASS hint only: land never merges
test-wrap-land: 18 sections, 18 ran, 0 cached (0 checks credited)
test-wrap-land: all 889 passed

Command: bash tests/test-wrap-merge.sh
  PASS hint after the URL: the squash fallback exits 0
  PASS hint after the URL: the replacement PR is #61
  PASS hint after the URL: no refusal
  PASS hint after the URL: #61 merged
  PASS hint only: the fallback names the missing PR number
  PASS hint only: the output did carry the PR URL mid-line
  PASS hint only: the mid-line URL is not taken as the replacement PR
  PASS hint only: the fallback merged nothing
test-wrap-merge: all 288 passed

Command: bash tests/test-wrap-carry.sh
  PASS autoland hint after the URL: apply exits 0
  PASS autoland hint after the URL: the PR number is read from the URL
  PASS autoland hint after the URL: the merge verifies
  PASS autoland hint after the URL: nothing failed
  PASS autoland hint only: the failure names gh pr create
  PASS autoland hint only: the output did carry the PR URL mid-line
  PASS autoland hint only: the mid-line URL is not taken as the PR
  PASS autoland hint only: no merge ran
test-wrap-carry: all 153 passed
Verdict: PASS
```

The gh stub (`tests/lib/wrap-stub.sh`) takes `GH_STUB_CREATE_HINT=after|only`. `after` prints the URL, then the hint block. `only` prints the block and no URL line. The block is the one gh prints: a `hint:` line, an indented `gh event listen --resource https://github.com/o/r/pull/<n> --event ...` line, and two `  - ...` lines.

## Negative control

Each control ran through `bash lib/gate/negctl.sh --parallel 3 "$PWD" "<suite>" <mutation>...` at `dd9919e1`, one run per suite. Every mutation edits the same three call sites: `lib/wrap/wrap-land.sh`, `lib/wrap/wrap-merge.sh`, `lib/wrap/wrap-carry.sh`.

### 1. The read before any fix: the last output line

```
Command: perl -pi -e 's/_pr_url_from_create "\$created" \|\| true/printf "%s\\n" "\$created" | tail -1/' lib/wrap/wrap-land.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-carry.sh
Exit: 1 under the mutation, 0 after restore
Output:
Changed: lib/wrap/wrap-carry.sh, lib/wrap/wrap-land.sh, lib/wrap/wrap-merge.sh
suite LAND_ONLY=happy bash tests/test-wrap-land.sh
  Exit: 1 (under mutation, RED expected)
  test-wrap-land: 46 passed, 4 FAILED of 50
suite bash tests/test-wrap-merge.sh
  Exit: 1 (under mutation, RED expected)
  test-wrap-merge: 285 passed, 3 FAILED of 288
suite bash tests/test-wrap-carry.sh
  Exit: 1 (under mutation, RED expected)
    FAIL autoland hint after the URL: the PR number is read from the URL
    FAIL autoland hint after the URL: the merge verifies
    FAIL autoland hint after the URL: nothing failed
    PASS autoland hint only: the failure names gh pr create
    PASS autoland hint only: no merge ran
  test-wrap-carry: 149 passed, 4 FAILED of 153
Restore: git checkout HEAD -- lib/wrap/wrap-carry.sh lib/wrap/wrap-land.sh lib/wrap/wrap-merge.sh
Exit: 0 (green after restore), all three suites
Verdict: PASS
```

The `hint after the URL` cases went red in each suite. The `hint only` cases stayed green, as they should: a last-line read also refuses a URL-less output.

### 2. A loose read: any PR URL anywhere in the output

```
Command: perl -pi -e 's/_pr_url_from_create "\$created" \|\| true/printf "%s\\n" "\$created" | grep -oE "https:\/\/[^ ]+\/pull\/[0-9]+" | tail -1/' lib/wrap/wrap-land.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-carry.sh
Exit: 1 under the mutation, 0 after restore
Output:
Changed: lib/wrap/wrap-carry.sh, lib/wrap/wrap-land.sh, lib/wrap/wrap-merge.sh
suite LAND_ONLY=happy bash tests/test-wrap-land.sh
  Exit: 1 (under mutation, RED expected)
    FAIL hint only: land exits 2
    FAIL hint only: land names the missing PR number
    FAIL hint only: the output did carry the PR URL mid-line
    FAIL hint only: the mid-line URL is not taken as the PR
    FAIL hint only: land never merges
  test-wrap-land: 45 passed, 5 FAILED of 50
suite bash tests/test-wrap-merge.sh
  Exit: 1 (under mutation, RED expected)
  test-wrap-merge: 285 passed, 3 FAILED of 288
suite bash tests/test-wrap-carry.sh
  Exit: 1 (under mutation, RED expected)
    PASS autoland hint after the URL: the PR number is read from the URL
    FAIL autoland hint only: the failure names gh pr create
    FAIL autoland hint only: the output did carry the PR URL mid-line
    FAIL autoland hint only: the mid-line URL is not taken as the PR
    FAIL autoland hint only: no merge ran
  test-wrap-carry: 149 passed, 4 FAILED of 153
Restore: git checkout HEAD -- lib/wrap/wrap-carry.sh lib/wrap/wrap-land.sh lib/wrap/wrap-merge.sh
Exit: 0 (green after restore), all three suites
Verdict: PASS
```

A read that takes the URL out of the `gh event listen` line opens and merges a PR from a hint. The `hint only` cases went red in each suite; the `hint after the URL` cases stayed green, because both URLs name the same PR there.

## Not proven

- That `|| true` fixes a live failure. A review read `bin/wrap`'s `set -euo pipefail` as reaching these call sites. It does not: `bin/wrap` execs `bash lib/wrap/wrap.sh`, a new shell that sets `-uo pipefail` and leaves `-e` out on purpose (`lib/wrap/wrap.sh`, the comment above its `set` line), and nothing else sources the wrap modules. The `hint only: land exits 2` row passed at `d9a65957`, before `|| true` existed, and the run below shows the same on all three suites. The `|| true` is kept as a statement of intent at a call that expects a non-zero return; it changes nothing today.
- Real gh. Every run used the stub. The stub's block copies the one gh 2.105.0 printed in this session after `gh pr checkout`; no PR was opened on GitHub by `wrap land`.
- A PR URL that gh prints on a line with other text before it. The parse needs the URL alone on its line (trailing whitespace allowed), which is what gh prints.
- The installed copy. This proof ran in the worktree; the installed kit picks the change up on its next update.

### The call shape without `|| true`: a check that cannot go red

```
Command: perl -pi -e 's/_pr_url_from_create "\$created" \|\| true/_pr_url_from_create "\$created"/' lib/wrap/wrap-land.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-carry.sh
Exit: 0 under the mutation
Output:
Changed: lib/wrap/wrap-carry.sh, lib/wrap/wrap-land.sh, lib/wrap/wrap-merge.sh
suite LAND_ONLY=happy bash tests/test-wrap-land.sh
  Exit: 0 (under mutation, RED expected)
    PASS hint only: land exits 2
    PASS hint only: land names the missing PR number
  test-wrap-land: all 50 passed
suite bash tests/test-wrap-merge.sh
  Exit: 0 (under mutation, RED expected)
  test-wrap-merge: all 288 passed
suite bash tests/test-wrap-carry.sh
  Exit: 0 (under mutation, RED expected)
  test-wrap-carry: all 153 passed
Result: negctl refused it, "test stayed green under the mutation (the check is vacuous)"
```

This run is not a proof and not a negative control. It records that no test can observe `|| true`.
