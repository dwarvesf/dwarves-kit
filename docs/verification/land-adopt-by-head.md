# Verification -- land-adopt-by-head

`wrap land` adopts the operator's own open PR by head commit when no PR carries the worktree branch's name, so a subagent that pushed under a renamed branch no longer gets a second PR.

## Green run

The land suite, with the new `adoptsha` section (one match adopts, two refuse, none opens a PR, a name match wins, another author's PR never counts), real git and a stubbed gh:

```
Command: bash tests/test-wrap-land.sh
Exit: 0
Output:
  test-wrap-land: 17 sections, 17 ran, 0 cached (0 checks credited)
  test-wrap-land: all 811 passed
Verdict: PASS
```

The other suites that run `land` (through `ship` and `adopt`) and the CLI table:

```
Command: bash tests/test-wrap-ship.sh && bash tests/test-wrap-adopt.sh && bash tests/test-wrap-cli.sh
Exit: 0
Output:
  test-wrap-ship: all 115 passed
  test-wrap-adopt: all 210 passed
  test-wrap-cli: all 22 passed
Verdict: PASS
```

## Negative control

Four mutations of `lib/wrap/wrap-land.sh`, each run through `lib/gate/negctl.sh` against `LAND_CACHE=0 LAND_ONLY=adoptsha bash tests/test-wrap-land.sh` after the fix was committed. Each went RED and was restored (green after restore, clean tree):

```
Command: bash lib/gate/negctl.sh "$PWD" "LAND_CACHE=0 LAND_ONLY=adoptsha bash tests/test-wrap-land.sh" "<mutation>"
Exit: 1 (under mutation, RED expected)
Output:
  adoption never fires (match count compared to 99):  29 passed, 7 FAILED of 36
  two matches no longer refuse (threshold 3):         27 passed, 9 FAILED of 36
  head sha filter dropped (any own PR matches):       24 passed, 12 FAILED of 36
  sha lookup also runs after a name match:            "asha name" checks FAILED
Verdict: PASS
```

## Not proven

- Real GitHub: gh is stubbed, so `headRefOid` freshness right after a push is not exercised.
- A by-head PR that turns CONFLICTING is refused with the PR left open; that path has no test case.
- The match is on the PR's head sha only; a head branch on origin ahead of or behind the worktree tip is not matched.
