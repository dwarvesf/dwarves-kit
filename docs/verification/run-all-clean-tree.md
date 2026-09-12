# Verification -- run-all-clean-tree

`tests/test-explain.sh`, `tests/test-quiz-gate.sh`, and `tests/test-weekend-batch.sh` each captured
a proof sample containing a run-specific value (a fresh fixture-commit SHA for the first two, a
fresh wall-clock timestamp for the third), so every `tests/run-all.sh` pass rewrote the three
tracked sample files (`docs/verification/{explain-command,quiz-gate,weekend-batch}/sample-*.md`)
and left the checkout dirty, which then blocks `lib/gate/negctl.sh`'s clean-tree requirement for
the next negative control (ID-830). Each test now `sed`-normalizes its run-specific value(s) to a
fixed placeholder before writing the sample.

## Premise check (before the fix)

Ran each owning test individually on the pre-fix code and diffed the committed sample against the
freshly-written one:

- `tests/test-explain.sh` -> `docs/verification/explain-command/sample-explainer.md`: only the
  fixture's commit SHA (embedded 3x: H1 title, blockquote base ref, "no recorded test result for
  \<sha\>") changed between two consecutive runs.
- `tests/test-quiz-gate.sh` -> `docs/verification/quiz-gate/sample-quiz.md`: same commit-SHA
  pattern (title line + "5-question understanding quiz for `<sha>`" line).
- `tests/test-weekend-batch.sh` -> `docs/verification/weekend-batch/sample-digest.md`: the
  `$NOW` wall-clock ISO-8601 timestamp, embedded 3x (`Window: since ...` + two `- recorded: ...`
  lines).

All other content (diff hunks, git blob SHAs from deterministic file content, question text,
disposition/significance fields) was byte-identical run to run; confirmed via direct diff of two
consecutive pre-fix runs.

## Green run

```
Command: bash tests/test-explain.sh && bash tests/test-quiz-gate.sh && bash tests/test-weekend-batch.sh
Exit: 0 / 0 / 0 (14/14, 33/33, 39/39 assertions PASS)
Verdict: git status --short after two consecutive runs from the committed HEAD (b6d207d) -> empty both times
```

Also ran the full meta suite and the lint entrypoint against the fix:

```
Command: bash tests/test-meta.sh
Exit: 0
Verdict: Passed: 852 / 852

Command: bash bin/lint --all
Exit: 0
Verdict: informational scattered-id report only, no new hits from this change
```

## Negative control

```
Command: git checkout c7f4d78 -- tests/test-explain.sh tests/test-quiz-gate.sh tests/test-weekend-batch.sh
          bash tests/test-explain.sh && bash tests/test-quiz-gate.sh && bash tests/test-weekend-batch.sh
          git status --short
Exit: 0 / 0 / 0 (tests themselves still pass; the tree is what breaks)
Verdict: dirty -- M docs/verification/explain-command/sample-explainer.md
                  M docs/verification/quiz-gate/sample-quiz.md
                  M docs/verification/weekend-batch/sample-digest.md
```

Restored via `git checkout HEAD -- tests/test-explain.sh tests/test-quiz-gate.sh
tests/test-weekend-batch.sh docs/verification/explain-command/sample-explainer.md
docs/verification/quiz-gate/sample-quiz.md docs/verification/weekend-batch/sample-digest.md`;
confirmed `git status --short` empty again.

## Not proven

- Does not cover every other `tests/test-*.sh` in the suite for similar run-specific-value
  capture bugs; ID-830 named these three files specifically (already a hand pass on the full
  suite per the row's source).
- Does not run the full `tests/run-all.sh` end to end (deliberately out of scope per the task's
  own instruction, to avoid the exact tree-dirtying this fix addresses becoming a confound); the
  three owning tests were run directly and repeatedly instead, which is what the row's own root
  cause and fix are scoped to.
