# Proof of done: transcript-measured skill listing + last-fired skills columns

## What changed

`session observe entry-fee`'s `skill_listing` component was sized from disk (SKILL.md
descriptions), an estimate. It carried no measure of the listing the model actually reads:
the literal text rendered into a `system-reminder` block, walked past a marker string
(`The following skills are available`) that can sit at different JSON paths across
transcript shapes (an `attachment` field in one shape, a user-message content block in
another).

`entry-fee` now adds a second, transcript-sourced bucket. For each session, the first
record whose string fields (walked generically, not a fixed path) carry the marker is
parsed: `- name: description` lines, an indented following line continuing the previous
description, the list ending at the first blank-line-then-non-entry. From that it reports
entry count, total listing chars, chars/4 as tokens, count of descriptions over 400 chars,
count of empty descriptions, and the top 8 by length, printed as its own table labelled
MEASURED-FROM-TRANSCRIPT, as a median across the sessions in the window plus the single
most recent session's own figures. The existing disk-sized split is now labelled
explicitly as estimated (`ESTIMATED from disk`), so the two buckets read as clearly
different units.

`session observe skills` gained a `14d` count (fires within the last 14 days of "now",
`SESSION_OBSERVE_NOW`-overridable, the same knob `burn` already uses) and a `last` column
(date of the most recent `Skill` tool_use), next to the existing count/errors/rate columns,
so a rotting skill (still counted, long unfired) is visible without a second scan.

## Gate table

| Claim | Evidence |
|---|---|
| the marker is found regardless of which JSON field carries it | `_walk_strings`/`_listing_block_text`, tests 91-96 (one fixture uses an `attachment` shape, the other a user-message content block) |
| entries parse correctly, including continuation lines and empty descriptions | tests 93-96 (delta's continuation, charlie's empty description) |
| a description over 400 chars is flagged | tests 93-96 (bravo, 450 chars) |
| the report shows a median across sessions plus the most recent session separately | tests 93, 94 |
| the disk-sized bucket is explicitly labelled an estimate | test 92 |
| the new section never leaks into `report` (entry-fee stays a standing measurement, not part of the weekly digest) | test 97 |
| skills gains `14d` and `last` without breaking the existing count/errors/rate columns | tests 88-90 |
| a skill fired only outside the 14d window still shows in count, not hidden, with `14d` 0 | test 89 |
| the whole module suite still holds | run table below |
| the change is load-bearing (not decorative) | negative control below |

## Run table

```
Command: bash lib/session/observe/tests/smoke.sh
Exit: 0
smoke: all 97 passed
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
run-all: 10 suites run, 0 skipped for missing tooling
run-all: FAILED -> test-no-personal-paths test-no-scattered-ids
```

The two failures are pre-existing and unrelated to this branch: `test-no-personal-paths`
flags operator paths already committed in `docs/verification/board-dedupe-absent.md` and
`docs/verification/wrap-start.md` (dwarves-kit #717/#718), and `test-no-scattered-ids`
flags pre-existing hits in `lib/board/board-run.sh` and `lib/board/board.sh`. This branch
touches only `lib/session/observe/bin/session-observe`, `lib/session/observe/tests/smoke.sh`,
and two new fixture files under `lib/session/observe/tests/fixtures/`, confirmed via
`git diff --stat origin/master` and `git log -- <those files>` (last touched by #717/#718,
weeks before this branch). The suites this branch is actually responsible for:

```
Command: bash lib/session/observe/tests/smoke.sh
Exit: 0
smoke: all 97 passed
```

```
Command: bash tests/test-meta.sh
Exit: 0
Passed: 854 / 854
All meta tests passed.
```

## Negative control

```
Command: git show HEAD~1:lib/session/observe/bin/session-observe >| lib/session/observe/bin/session-observe
Command: bash lib/session/observe/tests/smoke.sh
Exit: 1 (RED, expected)
smoke: 88 passed, 9 FAILED
  [88] fresh-skill row wrong (14d/last columns absent)
  [89] stale-skill row wrong (14d/last columns absent)
  [90] json skills wrong (count_14d/last keys absent)
  [91] measured section missing (MEASURED-FROM-TRANSCRIPT table absent)
  [92] disk-sized split not labelled (ESTIMATED from disk text absent)
  [93] median row wrong (skill listing median row absent)
  [94] most-recent row wrong (skill listing most-recent row absent)
  [95] top8 wrong (top-8 table absent)
  [96] json skill_listing_measured wrong (key absent)
```

```
Command: git checkout HEAD -- lib/session/observe/bin/session-observe
Command: bash lib/session/observe/tests/smoke.sh
Exit: 0 (green after restore)
smoke: all 97 passed
Verdict: PASS
```

Reverting `bin/session-observe` to the pre-change commit while keeping the new test cases
and fixtures fails exactly the 9 new assertions and nothing else; restoring the file returns
to all 97 green. The tests exercise real behavior, not vacuous checks.
