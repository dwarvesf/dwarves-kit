# Verification -- board-expire-by-age

`board mirror-cleanup` gains an age expiry: a rule in the kinds file with an `expire` block archives the bot-made cards of its kind that sat in triage past the limit, on the named board only. `board sweep --expire-kinds-file F` runs it every tick. First user: the personal Hermes board `social`, 14 days.

## Gate table

| Claim | Evidence |
|---|---|
| a dry run reports what would expire and when the next card crosses, and archives nothing | green run 1, AC1 |
| apply archives exactly the eligible cards (at or past the limit, triage, the listed board) and prints one line | green run 1, AC2 and AC3 |
| a second apply expires 0 | green run 1, AC4 |
| no expire block means no expiry; a bad block or a missing rule is refused | green run 1, NC1 to NC3 |
| the sweep leg runs once per tick, only dry-runs under `--dry-run`, never flips the exit code | green run 2 |
| the live board reports 0 to expire today | live dry run |
| the guards are load-bearing | negative controls |

## Green run

```
Command: bash tests/test-board-mirror-expire.sh
Exit: 0
Output:
AC1: dry run
  ok   the line says what would expire: s1 s2 s5 s10 is 4
  ok   it names when the next card crosses the limit
AC2/AC3: apply
  ok   one line: expired 4 cards on social (limit 14d)
  ok   boundary: one hour short, young, not triage, no created_at, closed, mirror card all stay
  ok   another board's card stays, even from the same creator
  TOTAL: 31   PASS: 31   FAIL: 0
Verdict: PASS
```

```
Command: bash tests/test-board-sweep-expire.sh && bash tests/test-board-mirror-cleanup.sh && bash tests/test-board-sweep.sh && bash tests/test-board-sweep-mirror.sh
Exit: 0
Output:
  TOTAL: 14   PASS: 14   FAIL: 0
  TOTAL: 31   PASS: 31   FAIL: 0
PASS=55 FAIL=0
PASS=43 FAIL=0
Verdict: PASS
```

## Live dry run

Read-only, against the real personal Hermes store, with the operator's rule list:

```
Command: HERMES_HOME=$HOME/hermes-personal/home bin/board mirror-cleanup --expire-only --kinds-file <ops-toolkit>/tools/board-sync/config/mirror-kinds.json
Exit: 0
Output:
would expire 0 cards on social (limit 14d)
next card on social crosses 14d at 2026-10-07 20:23 +07
Verdict: PASS (97 triage cards, oldest created 2026-09-23 20:23 +07)
```

## Negative control

```
Command: invert the limit comparison (>= to <), then bash tests/test-board-mirror-expire.sh
Exit: 1
Output:
  FAIL the line says what would expire: s1 s2 s5 s10 is 4
  FAIL one line: expired 4 cards on social (limit 14d)
  FAIL archived exactly the eligible cards
  FAIL boundary: one hour short, young, not triage, no created_at, closed, mirror card all stay
Verdict: RED as intended
```

```
Command: drop the board scoping (`if rule and rule["expire"]["board"] == slug` to `if rule`), then bash tests/test-board-mirror-expire.sh
Exit: 1
Output:
  FAIL plain apply leaves the same creator's old card on another board alone
  TOTAL: 31   PASS: 30   FAIL: 1
Verdict: RED as intended
```

```
Command: make the sweep leg always pass --apply, then bash tests/test-board-sweep-expire.sh
Exit: 1
Output:
  FAIL --apply passed on a dry run
  TOTAL: 14   PASS: 13   FAIL: 1
Verdict: RED as intended
```

Each mutation was reverted with `git checkout --` after a commit; the suites are green again.

## Not proven

- No live archive: this change was never run with `--apply` against the real store.
- The sweep leg is proven with a stub `board`; the first real tick is the first real run.
