# Proof of done: writeback ignores a card still in its mirror-created column

## The defect

`board writeback --dry-run` proposed walking board rows BACKWARDS on its first live run
(8 rows across 4 repos, recorded in ops-toolkit `docs/verification/board-writeback-live-roundtrip.md`).

Root cause: `lib/board/board-mirror.sh` builds its CHANGE op as `kanban comment` (line ~475), so the
mirror never moves a card after creating it. The apply-plan result line nonetheless records
`hermes_status: target_native`, the INTENDED column. The snapshot therefore stores an intent the
card never reached, and `board-writeback.sh`'s live-vs-snapshot comparison read that disagreement
as a human move.

## The fix

`_created_native <board> <id>` reads the card's own `created` event
(`hermes kanban show --json`). A card whose live status still equals its create column was never
moved, so the row is skipped and reported. One `show` call per CANDIDATE row only; the batched
per-board `list` is unchanged. The git-wins `row_hash` rule is untouched.

## Acceptance criteria

| AC | Claim | Proof |
|---|---|---|
| AC6a | a card in its create column produces ZERO writeback changes | `test-board-writeback.sh` AC6 cases 1-3 |
| AC6b | a card that really moved still produces exactly one change | `test-board-writeback.sh` AC6 case 4 |
| AC6c | the skip is reported with the column and counted as skipped, not as a change | `test-board-writeback.sh` AC6 cases 3, 5 |
| AC6d | hermes unable to answer (no created event) degrades to the prior behavior | stub answers `{}` for unmapped ids; AC2/AC3/NC1-NC6 stay green |
| LIVE | the live dry-run stops proposing the phantom moves | run table below |

## Recorded run

```
Command: bash tests/test-board-writeback.sh
Exit: 0
TOTAL: 59   PASS: 58   FAIL: 0   SKIP: 1
  PASS AC6: exactly ONE changeset entry (the moved card only)
  PASS AC6: the card in its create column (ID-001) produces ZERO changeset entries
  PASS AC6: the create-state skip is reported by name, with the column
  PASS AC6: the MOVED card (ID-003, created 'blocked', now 'done') still writes back parked -> shipped
  PASS AC6: the summary counts the create-state row as skipped, not as a change

Command: bash tests/run-all.sh --changed
Exit: 0
run-all: all 14 suites passed, 0 skipped for missing tooling
```

## Live run (read-only, on the Mini, against the real Hermes and the scheduled mirror snapshot)

Same registry, same snapshot, same live board, two libs. The apply was NOT run.

```
Command: bash <kit>/lib/board/board-writeback.sh diff --registry <ops-toolkit>/_meta/boards.txt \
           --snapshot <ops-toolkit>/_meta/.board-mirror-snapshot-personal.jsonl
Baseline (master):  writeback: 7 change(s), 4 skipped
Treatment (branch): writeback: 5 change(s), 6 skipped
Delta: 3 phantom rows removed, 0 genuine rows lost
```

The three rows the fix removed, each with the reason it printed:

```
skip context-kit:CK-27:    card still sits in its mirror-created column 'triage' (never moved; snapshot recorded intent 'ready')
skip neko:NK-004:          card still sits in its mirror-created column 'ready'  (never moved; snapshot recorded intent 'blocked')
skip ops-toolkit:ID-912:   card still sits in its mirror-created column 'triage' (never moved; snapshot recorded intent 'ready')
```

The 5 rows that remain are all console-labs cards (CL-002, CL-003, CL-005, CL-006, CL-030) that
were created in `triage` and now sit in `blocked`. They genuinely left their create column, so
this rule does not cover them and must not: something moved them. Whether a `blocked` Hermes card
should park a `queued` git row is a separate judgment, not a create-state phantom. The original
run's 8th row (ops-toolkit:ID-912 as a git `executing` row) had already left the extraction by
today's run for an unrelated reason; the rule now catches it explicitly either way.

## Negative control

```
Command: bash tests/test-board-writeback.sh, with the create-state guard neutered
         (`if false && [ -n "$created_status" ] ...`)
Exit: 1
TOTAL: 59   PASS: 54   FAIL: 4   SKIP: 1
  FAIL AC6: exactly ONE changeset entry (the moved card only)
  FAIL AC6: the card in its create column (ID-001) produces ZERO changeset entries
  FAIL AC6: the create-state skip is reported by name, with the column
  FAIL AC6: the summary counts the create-state row as skipped, not as a change
  PASS AC6: the MOVED card (ID-003, created 'blocked', now 'done') still writes back parked -> shipped
```

Restored with `git checkout -- lib/board/board-writeback.sh`; the suite returns to 58 PASS / 0 FAIL.
The one case that stays green under the mutation is the control on the control: the fix must not
suppress a genuine move.

## Not fixed here

`board-mirror.sh` still records the INTENDED column in the snapshot on a CHANGE op. The writeback
no longer trusts that value for the move test, so the defect is closed at the consumer. Making the
mirror record only what it observed is a separate change with its own test surface.
