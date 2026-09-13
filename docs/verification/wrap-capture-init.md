# A full-lane capture with no board runs `board init` first

`commands/wrap.md` step 7b's `full`-lane branch tells the operator to run `bin/board capture
... --backlog-file <home>/_meta/BACKLOG.md`. On a freshly adopted repo with no
`_meta/BACKLOG.md`, `capture` refuses with exit 2 and `no board at <path> (run \`board
init\`)` (`lib/board/board.sh:860`). `wrap.md` said nothing about that case, so the sub-step
dead-ended for a new adopter.

## The change

1. One sentence after the `capture` code block in `commands/wrap.md`: on a `capture` exit 2
   for a missing board, run `bin/board init` from the home repo's root (idempotent, scaffolds
   `_meta/BACKLOG.md` + the `_meta/board` shim per `lib/board/board.sh:813-842`, the same
   thing `/kit:onboard` offers) then run `capture` again. Any other non-zero exit closes the
   candidate as `(lane=full, capture failed: <first line of stderr>)`, and the goal draft is
   still written.
2. `lib/wrap/report-lint.sh` accepts `capture failed:` as a fourth lane closure alongside
   `verified:`, `filed:`, and `staged`, since the new failure path is a legitimate way for a
   `lane=full` item to close.
3. `tests/test-wrap.sh` gets one new case beside the `filed:` cases from PR #621, asserting the
   `capture failed:` shape passes the lint.

## Green run

- Command: `bash tests/test-wrap.sh`
- Exit: 0
- Output: `test-wrap: all 369 passed` (368 before this change, one new assertion)
- Verdict: PASS

| Case | Fixture `**Built:**` value | Expected | Got |
|---|---|---|---|
| full-lane capture-failed closure | `... (lane=full, capture failed: no board at _meta/BACKLOG.md)` | exit 0 | exit 0 |

Every pre-existing lane case (`filed:`, `staged`, `staged` rejected on `lane=full`, a lane with
no closure, the LIST form) still passes.

## Negative control

Produced with `lib/gate/negctl.sh` after the change was committed.

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh >/dev/null 2>&1
Exit: 0 (green before mutation)
Mutation: perl -pi -e 's/capture failed:/XXXXXXXXXXXXXX:/g' lib/wrap/report-lint.sh
Changed: lib/wrap/report-lint.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/report-lint.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation blinds the lint to the `capture failed:` closure, so the new case's `lane=full`
item reads as a lane with no closure and the suite goes red. Restoring the file goes green
again, so the new assertion constrains the token it names.

## Reproduce

```bash
cd ~/.claude/dwarves-kit
bash tests/test-wrap.sh
```

## What this does not cover

This is a documentation change to `wrap.md` plus a lint-acceptance change; it does not
exercise a live `bin/board init` + `bin/board capture` retry end to end against a real missing
board (that mechanism already exists and is unchanged, proved in `wrap-full-to-board.md`). The
lint change only widens what closure text it accepts; it cannot see whether an operator
actually ran `board init` before retrying `capture`.
