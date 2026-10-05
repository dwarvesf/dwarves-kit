# Verification: hooks-wrap-usage

`gate-ledger.sh` prints argument signatures for `start`, `record`, `override` and `debt` on a bare or unknown verb. `docs/hooks.md` maps each hook message to its source. `docs/wrap.md` is a verb-by-situation table. No new flag and no behavior change.

## Green run

```
Command: bash tests/test-gate-ledger-usage.sh
Exit: 0
Output:
    PASS bare: exits 64
    PASS bare: keeps the verb list
    PASS bare: start signature
    PASS bare: record signature
    PASS bare: override signature
    PASS bare: debt signature
    PASS no-such-verb: exits 64
    PASS no-such-verb: keeps the verb list
    PASS no-such-verb: start signature
    PASS no-such-verb: record signature
    PASS no-such-verb: override signature
    PASS no-such-verb: debt signature

  gate-ledger usage: 12/12 passed
Verdict: PASS
```

```
Command: bash bin/test-affected
Exit: 0
Output: test-affected: 49 selected, 49 pass, 0 cached, 0 fail, 0 timeout, 0 uncovered
Verdict: PASS
```

The hook table was checked two ways. A script compared the 26 scripts wired in `hooks/hooks.json` to the table rows and found no difference. Each quoted message prefix was matched against its source file with `grep -F`, and every one matched.

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-gate-ledger-usage.sh" "git show origin/master:lib/gate/gate-ledger.sh > lib/gate/gate-ledger.sh"
Exit: 1 (under mutation, RED expected)
Output:
    FAIL bare: override signature
    FAIL bare: debt signature
    PASS no-such-verb: exits 64
    PASS no-such-verb: keeps the verb list
    FAIL no-such-verb: start signature
    FAIL no-such-verb: record signature
    FAIL no-such-verb: override signature
    FAIL no-such-verb: debt signature

  gate-ledger usage: 4/12 passed
Verdict: PASS
```

The mutation restored the pre-change `gate-ledger.sh` from `origin/master`. The suite went from 12/12 to 4/12. `negctl.sh` then restored the file with `git checkout HEAD -- lib/gate/gate-ledger.sh` and the suite returned to green.

## Not proven

- The `docs/wrap.md` and `docs/hooks.md` rows are read from source and spot-run (`wrap start --help`, `wrap start` on a bare name, `wrap start` on an existing branch, `wrap merge` and `wrap apply --own` dry runs). Rows for `land`, `rebase` and `adopt` come from reading the code, not from a live run.
- No test pins the prose in either doc. A later code change can make a row stale.
