# Verification -- commit-format-multiline-m

The commit-format hook now lints only the first line of the first message argument, so one multi-line message argument (subject, blank line, long body) no longer blocks as "subject is N chars".

## Green run
```
Command: bash tests/test-hooks.sh
Exit: 0
Output:
=== commit-format.sh ===
  PASS blocks non-conventional subject (exit 2)
  PASS blocks spec-ID in subject (exit 2)
  PASS blocks subject over 72 chars (exit 2)
  PASS allows a clean conventional subject (exit 0)
  PASS allows long body via second -m (subject-only lint) (exit 0)
  PASS allows long body inside one multi-line -m (first line is the subject) (exit 0)
  PASS blocks 74-char first line of a multi-line -m (exit 2)
  PASS blocks non-conventional first line of a multi-line -m (exit 2)
  PASS allows editor commit (no -m) (exit 0)
  PASS allows amend --no-edit (exit 0)
  PASS ignores non-commit commands (exit 0)
  ...
=== Results ===
Passed: 818 / 818
All tests passed.
Verdict: PASS
```

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-hooks.sh" "git show origin/master:hooks/commit-format.sh > hooks/commit-format.sh"
Exit: 0
Output:
Mutation: the pre-fix hook restored from origin/master
Exit: 1 (under mutation, RED expected)
  FAIL allows long body inside one multi-line -m (first line is the subject) (expected exit 0, got 2)
  FAIL blocks non-conventional first line of a multi-line -m (expected exit 2, got 0)
=== Results ===
Passed: 816 / 818
Failed: 2
Restore: git checkout HEAD -- hooks/commit-format.sh
Exit: 0 (green after restore)
Verdict: PASS
```
The pre-fix hook fails two of the three new cases. The 74-char first-line case already blocked before the fix (the whole message was over 72), so it guards the first-line cut against loosening the length check. The hook was restored and the suite is green again.

## Not proven
- Only real newlines inside the quoted message argument are handled; a `$'...'` string with escaped newlines was never parsed by this hook and still is not.
- Which message argument is "first" is unchanged: the existing regex order applies, so a `--message` form still wins over `-m`.
