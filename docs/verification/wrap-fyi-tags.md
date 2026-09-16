# Proof of done: FYI lines carry a tag and never an ask

2026-09-17. The `/kit:wrap` report closes with an `**FYI:**` block. Real reports mixed four
kinds of line under that one header: a step that did not run, a state the operator meets next
session, an incident during the pass, and an ask wearing prose. An operator told to "follow
the FYI" reads nine lines and picks a meaning per line. The report already has a home for
asks, the lettered `Needs you` block with its DECIDE, RUN, REVIEW and UNBLOCK tags.

Every `**FYI:**` bullet now opens with `SKIPPED`, `STATE`, or `INCIDENT`, the same shape the
`**Built:**` verdict words landed in earlier. `lib/wrap/report-lint.sh` fails an untagged
bullet, and fails a bullet whose text reads as an ask.

Two lines from tonight's real report, before and after:

| Before (one untagged block) | After |
|---|---|
| `- wrap.pull_past_dirty is false ... turning the knob on now works cleanly` | `Needs you` item: `a. DECIDE whether to set wrap.pull_past_dirty true. ...` The `FYI` keeps the fact alone: `- STATE wrap.pull_past_dirty is false, the ops-toolkit checkout stayed behind` |
| `- dotfiles scripts/test-doc-discipline.sh fails on two pre-existing scripts` | `Needs you` item: `a. RUN the doc-discipline fix on the two pre-existing scripts. ...` or, kept as a fact with its home named: `- STATE dotfiles scripts/test-doc-discipline.sh fails on two pre-existing scripts, tracked at <path>` |

## Green run

Command: `bash tests/test-wrap.sh`
Exit: 0
Output: `test-wrap: all 528 passed`
Verdict: PASS

Command: `bash tests/run-all.sh` (bare, diff-scoped plus the six always-on lints)
Exit: 0
Output: `run-all: --changed against 6bdea6a: 4 changed files -> 9 suites (3 named, the rest
always-on)`, then `run-all: all 9 suites passed, 0 skipped for missing tooling`
Verdict: PASS

## NEGATIVE CONTROL

Command: `git checkout origin/master -- lib/wrap/report-lint.sh && bash tests/test-wrap.sh`
Exit: 1
Red lines, exactly the four new failing-case assertions and nothing else:

```
  FAIL an untagged FYI bullet fails
  FAIL the finding names the three tags
  FAIL a tagged FYI bullet carrying an ask fails
  FAIL the finding sends the ask to Needs you
test-wrap: 524 passed, 4 FAILED of 528
```

Restore: `git checkout HEAD -- lib/wrap/report-lint.sh`, then `bash tests/test-wrap.sh` is
`test-wrap: all 528 passed` again.
Verdict: PASS

## Not proven

The ask rule is a word list, not a meaning test. The regex matches `should`, `consider`,
`recommend`, `you can`, `turn(ing) <knob> on`, `works cleanly`, `worth a/an/the/doing/turning`,
`next time run`, and `please`. An ask phrased around none of those words passes the lint. The
rule catches the phrasings the real reports used; it does not decide intent, and the tag
itself stays the operator-facing discipline.

The three tags are checked for presence, not for correctness. A bullet tagged `STATE` that
describes an incident passes.
