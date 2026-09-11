# Proof of done: report-lint warns on a NEW Built item that drives CDP

Change: `lib/wrap/report-lint.sh` gains one more check. When a wrap report's `**Built:**`
line carries a `NEW (precedent: nothing matched): <path>` item whose path (relative to the
current repo, or absolute) exists AND the files under it call the browser-harness CDP
surface (`grep -E 'session\.(Runtime|Input|DOM|Page|Target)\.|listPageTargets\(|Runtime\.evaluate'`,
over the path when it is a file, or recursively when it is a directory), the lint prints a
`warn:` line naming the browser-harness-js learnings home, without failing (exit stays 0
unless another rule fires). ENHANCE items are never scanned, only NEW candidates: the path
extraction keys off the literal `NEW (precedent: nothing matched):` substring.

## Recorded run (2026-09-10, Air)

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/test-wrap.sh` (258 cases, incl. 3 new: NEW+CDP warns, ENHANCE+CDP never checked, NEW+plain no warn) | 0 | PASS 258/258 |

## Negative control (`lib/gate/negctl.sh`)

```
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/HARNESS_CDP_RE=.*/HARNESS_CDP_RE=nomatchxxxxx/' lib/wrap/report-lint.sh
Changed: lib/wrap/report-lint.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/report-lint.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Docs touched

`commands/wrap.md`'s `**Built:**` bullet gains one sentence naming the new warn behavior.
`docs/FEATURES.md` was checked and does not reference `report-lint`, so it was left alone
per the task's own instruction to skip when the feature registry does not cover it.

## Rollback

Revert the commit; the lint returns to checking only the three-state `Built:`/`Seam:`
coverage and the `Needs you` admission test, with no harness-shape warn.
