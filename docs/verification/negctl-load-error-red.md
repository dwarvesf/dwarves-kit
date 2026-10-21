# Proof of done: negctl refuses a load-error RED

Lane: normal

## What changed

`lib/gate/negctl.sh` took any non-zero exit under the mutation as RED. A sed that broke the
source's syntax made vitest fail to load the file (`Test Files  1 failed (1)`, `Tests  no tests`,
an esbuild transform error), and negctl printed `Verdict: PASS` although the test's assertion
never ran.

`red_load_error()` now reads the captured RED output. A load or compile signature with no
assertion-failure signal is `Verdict: FAIL: RED was a load or compile error, not a failing test
(<matched line>)`, exit 1, restore as usual. Any assertion signal keeps the RED valid.
A load-error RED is never retried under `NEGCTL_RED_ATTEMPTS`. `NEGCTL_ALLOW_LOAD_RED=1` restores
the old behaviour. The mutate, `--at` and `--parallel` modes share the check; `--base-ref` does not.

## Gate table

| Claim | Evidence |
|---|---|
| vitest `Tests  no tests` RED is FAIL with the matched line named, tree restored | case 46 |
| `NEGCTL_ALLOW_LOAD_RED=1` accepts the same RED | case 47 |
| `Tests  1 failed` plus `SyntaxError` still counts as RED | case 48 |
| a load-error RED is not retried under `NEGCTL_RED_ATTEMPTS=3` | case 49 |
| a real bash syntax error is FAIL in mutate and `--at` modes | case 50 |
| all earlier negctl cases hold | cases 1 to 45 |
| the check is load-bearing | negative control below |

## Green run

```
Command: bash tests/test-proof-negctl.sh
Exit: 0
Output:
[46] a RED that is a vitest load error (Tests  no tests) is FAIL, restored, tree clean
  ok: load-error RED rejected, matched line named
[47] NEGCTL_ALLOW_LOAD_RED=1 restores the old behaviour: the same RED is PASS
  ok: escape hatch accepts the load-error RED and says so
[48] an assertion failure beside a load signature (Tests  1 failed + SyntaxError) still counts as RED
  ok: assertion signal wins over the load signature
[49] a load-error RED is never retried under NEGCTL_RED_ATTEMPTS=3
  ok: FAIL on attempt 1, no later attempt
[50] a real bash syntax error from the mutation is FAIL; the --at mode judges it the same way
  ok: bash syntax error rejected in mutate and --at modes
test-proof-negctl: all 51 passed
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
run-all: all 51 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

Mutation: `red_load_error()` returns 1 before reading the output (the line
`grep -aqE "$re_assert" "$f" && return 1` becomes `return 1`), so no RED is ever called a load
error. Run against the committed change (a8075b9c).

```
Command: bash lib/gate/negctl.sh <worktree> "bash tests/test-proof-negctl.sh" "<sed on lib/gate/negctl.sh>"
Exit: 1 (under mutation, RED expected)
Output:
  Exit: 1 (under mutation, RED expected)
  Output:
    ./lib.sh: line 1: syntax error near unexpected token `fi'
    ./lib.sh: line 1: `fi'
    test.sh: line 4: add: command not found
  Restore: git checkout HEAD -- lib.sh
  Exit: 0 (green after restore)
  Verdict: PASS
  test-proof-negctl: 47 passed, 4 FAILED
Restore: git checkout HEAD -- lib/gate/negctl.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Cases 46, 49 and 50 (mutate and `--at`) failed under the mutation: 4 assertions. The file was
restored and the suite is green again. Re-running the logged Command reproduces the verdict.

## Not proven

- Real vitest, pytest, jest and go output: the fixtures print the signature lines by hand. The
  bash syntax error case is the only one produced by a real runner.
- `--base-ref` mode is deliberately unchanged: a missing module at the old ref is the expected
  way for the change under test to be absent.
