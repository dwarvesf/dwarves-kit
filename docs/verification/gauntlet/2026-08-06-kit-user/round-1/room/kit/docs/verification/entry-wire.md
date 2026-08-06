# Proof of done: session-start board wire (SPEC-083 / ID-033)

## Acceptance criteria

| AC | Claim | Proof |
|---|---|---|
| AC1 | `board:<N>q` token when `_meta/BACKLOG.md` exists; none without | fixtures "board token counts leading-queued only", "no board file -> no board token", "board with 0 queued emits 0q token" |
| AC2 | queue suggestion = "state the task" + `/kit:assign --next` | fixtures "no-spec + queue: intent-first phrasing", "names /kit:assign --next" |
| AC3 | no-board no-spec suggestion intent-first | fixture "no-spec no-board: intent-first line" |
| AC4 | live-spec cycle suggestion beats board pull, token stays | fixtures "live spec: cycle suggestion wins...", "board token still present", "board-pull suggestion absent" |
| AC5 | every rewired string pinned, intent before command | DRAFT/review/ship/continue fixtures + meta pin "4+ say-branches" |
| AC6 | MANUAL board mentions | meta pins "MANUAL /kit:start Reads mentions the board", "MANUAL hook row carries the board token" |
| AC7 | suites green + NC | run table below |

## Implementation

`hooks/context-readiness.sh` (board-count awk, twin of `lib/board/backlog.sh _rows`;
6 intent-first SUGGEST strings; live-spec precedence), `MANUAL.md` (2 lines),
`tests/test-hooks.sh` (+14), `tests/test-meta.sh` (+6).

## Confirmation runs

| Run | Command | Result |
|---|---|---|
| failing-first | `bash tests/test-hooks.sh` pre-implementation | 11 RED (3 not-contains pins trivially green, expected) |
| green | all three suites post-implementation | hooks 426/426 x3 consecutive, meta 479/479, e2e 20/20 |
| negative control | board-token emission line replaced with no-op, hooks suite | 3 RED (board:2q x2, board:0q), restored, green |

Known noise: the pre-existing ID-081 PTY flake (gate-ledger progress color
test) fired in 3 mid-cycle runs; never a SPEC-083 pin. 4th sighting captured
to `docs/research/2026-06-11-id081-flake-capture.txt`, board row updated.

Verdict: PASS (claim: the SessionStart hook emits the board token and
intent-first suggestions per the SPEC-083 matrix; metric: fixture pins;
threshold: 14/14 green with the negative control flipping 3 RED).

## Reproduce

```
bash tests/test-hooks.sh   # SPEC-083 block: grep -n 'SPEC-083' tests/test-hooks.sh
bash tests/test-meta.sh    # === SPEC-083 === section
```
