# Verification -- board brief, one daily message per cluster

`board brief run` (`lib/sync/sweep/board-brief`) builds on the `board health` engine. It posts ONE message per cluster per day: what needs the operator's decision, open incidents (an `--incidents` hook), the boards on a slower clock, one line of what bots did. Details travel in `payload.details`. `board health run` and `board brief run` also read their flags from a JSON config file. Two Hermes skills (`adapters/hermes/skills/`) name which command answers which question and hold no logic.

## Gate table

| Claim | Evidence |
|---|---|
| a hub row whose state and mirror card disagree becomes one question ending `Ship or reopen?` | green run, case decisions |
| three decision lines show, the rest are named and sit in the details | green run; negative control 3 |
| incident rows marked `needs_you` and explicit hook decisions are decisions | green run, case incident hook |
| bot counts show as given, zeros dropped; archived and sync errors join them | green run, cases incident hook and bots line |
| a failing or malformed hook is a fault line, never an all-clear | green run; negative control 2 |
| hook text keeps rule names whole and masks hex runs, secret references, webhook URLs | green run, case hook text; negative control 6 |
| the hook is told when the run is a preview or a test (`BOARD_BRIEF_READ_ONLY=1`) | green run, case hook flag; negative control 5 |
| `--decisions-only` posts nothing while clean (and stamps), and only decision lines otherwise | green run; negative control 4 |
| the boards section shows on the first run, every third day, or on a decision, else rides the details; a sync fault does not bring it back | green run; negative control 1 |
| due once a day; `--force` overrides; `--dry-run` and `--no-state` write no brief state | green run, case cadence |
| a failed post is not stamped, rides `carried_error`, clears on delivery | green run, case failed post |
| `--config`, `$DWARVES_BOARD_CONFIG`, and the default path feed the flags; a bad file is an error | green run, case --config |

## Green run

```
Command: bash tests/test-board-brief.sh && bash tests/test-board-health.sh && bash tests/test-board-sweep.sh
Exit: 0
Output:
  ok   board brief run --help

board-brief: 110 passed, 0 failed
board-health: 96 passed, 0 failed
PASS=55 FAIL=0
Verdict: PASS
```

## Format revision (headings, links, bold question)

The first live TEST was flat text. The revision renders each section under a Discord small heading with a blank line between sections, ids as masked links with the preview suppressed (inline code when there is no URL), the question in bold, hosts after `@` in inline code, and the same rules in the details message. `render.ts` in event-bridge appends the body to the head line with a plain newline, so blank lines and `###` headings survive; only `@everyone` and `@here` are defanged.

| Claim | Evidence |
|---|---|
| sections sit under `###` headings, each heading after the first follows a blank line, in the details too | green run, case formatting; negative control 9 |
| a board row id links to its line in the GitHub copy of the board; inline code when the board is not on GitHub | same case; negative control 7 |
| a hook row id links to its URL; an http URL or one with markup characters is refused | same case; negative control 11 |
| every link has its URL in angle brackets (no preview) | same case; negative control 10 |
| the decision question is bold, a host after `@` is inline code | same case; negative control 8 |
| the main message stays under `--main-chars`: boards move to the details, then the incident rows past the first | same case; negative control 12 |

Controls 7 to 12, mutations applied on a committed tree and reverted:

```
Control 7: row ids are not linked (row_link returns inline code)       -> FAIL the shipped row with an open card is a question; board-brief: 107 passed, 3 failed
Control 8: the question is not bold (bold_question returns the text)   -> FAIL the decision question is bold; board-brief: 108 passed, 2 failed
Control 9: no blank line between sections (the gap is dropped)         -> FAIL a heading follows text with no blank line; board-brief: 109 passed, 1 failed
Control 10: link preview not suppressed ([t](url) instead of [t](<url>)) -> FAIL a ticket id is a masked link with the preview suppressed; board-brief: 106 passed, 4 failed
Control 11: a hook URL is not validated (the URL check removed)        -> FAIL an http URL is refused: the id is inline code; board-brief: 108 passed, 2 failed
Control 12: the budget is ignored (the boards demotion removed)        -> FAIL over the budget the boards block moves to the details; board-brief: 107 passed, 3 failed
```

## Negative controls

Each mutation was applied on a committed tree and reverted with `git checkout --`.

```
Control 1: the boards section always shows (`show_boards = bool(args.show_boards or decisions or slow_clock)` became `show_boards = True`)
Command: bash tests/test-board-brief.sh
Exit: 1
Output:
  FAIL the next day hides the boards lines
  FAIL they ride the details
  FAIL a sync fault does not bring the boards back
```

```
Control 2: an unreadable incident feed still says all clear (`elif not only and not feed_faults:` became `elif not only:`)
Command: bash tests/test-board-brief.sh
Exit: 1
Output:
  FAIL and no all-clear line
board-brief: 86 passed, 1 failed
```

```
Control 3: decisions are not capped at three (`shown = decisions[:MAX_DECISIONS]` became `shown = decisions`)
Command: bash tests/test-board-brief.sh
Exit: 1
Output:
  FAIL the rest is named, not dropped
  FAIL the rest is in the details
board-brief: 85 passed, 2 failed
```

```
Control 4: --decisions-only posts when clean (`if only and not payload["attention"]:` became `if False:`)
Command: bash tests/test-board-brief.sh
Exit: 1
Output:
  FAIL decisions-only posts nothing when clean
  FAIL a config file alone runs the brief
board-brief: 85 passed, 2 failed
```

```
Control 5: the hook is not told about a preview (`env = dict(os.environ, BOARD_BRIEF_READ_ONLY="1") if read_only else None` became `env = None`)
Command: bash tests/test-board-brief.sh
Exit: 1
Output:
  FAIL --dry-run sets BOARD_BRIEF_READ_ONLY (got 'unset', want '1')
  FAIL --no-state sets it too (got 'unset', want '1')
board-brief: 85 passed, 2 failed
```

```
Control 6: every 24-character name is masked as a token (the hook-text masking regex became `[A-Za-z0-9_-]{24,}`)
Command: bash tests/test-board-brief.sh
Exit: 1
Output:
  FAIL a long rule name is not masked
board-brief: 86 passed, 1 failed
```

## Reproduce

```
bash tests/test-board-brief.sh
bash tests/test-board-health.sh
```
