# Verification -- ship-gate-heredoc

Ship-gate command parsing matches bash on heredoc terminators, quoted heredoc openers, command substitutions, and gh global flags.

## Green run
```
Command: bash tests/test-ship-gate-command-words.sh
Exit: 0
Output:
  ok - ship step after a heredoc -> engaged
  ok - ship step on the opener line -> engaged
  ---
  PASS=97 FAIL=0
Verdict: PASS
```

## Negative control
```
## Negative control (negctl)
Command: bash tests/test-ship-gate-command-words.sh
Exit: 0 (green before mutation)
Output:
  ok - quoted create word -> engaged
  ok - heredoc body prose -> not engaged
  ok - commit message heredoc -> not engaged
  ok - commit message in a substitution -> not engaged
  ok - quoted <<X, nothing else -> not engaged
  ok - quoted <<X, quoted prose after it -> not engaged
  ok - ship step after a heredoc -> engaged
  ok - ship step on the opener line -> engaged
  ---
  PASS=97 FAIL=0

Mutation: git show origin/master:hooks/ship-gate.sh > hooks/ship-gate.sh
Changed: hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)
Output:
  NOT ok - quoted create word -> should engage (exit 2)
  ok - heredoc body prose -> not engaged
  ok - commit message heredoc -> not engaged
  ok - commit message in a substitution -> not engaged
  ok - quoted <<X, nothing else -> not engaged
  ok - quoted <<X, quoted prose after it -> not engaged
  ok - ship step after a heredoc -> engaged
  ok - ship step on the opener line -> engaged
  ---
  PASS=57 FAIL=40

Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```
