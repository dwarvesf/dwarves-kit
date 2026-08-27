# ID-484: web-drift refuses to run against a boardless consumer

## Claim

Decided with Han (session lead, delegated): `kit:web-drift` REFUSES THE RUN
against a target repo with no `_meta/BACKLOG.md`, naming the fix (`bin/board
init` in that repo), rather than keeping a local per-consumer ledger. web-drift
is a prose SKILL.md (no lib/ script backs the Apply step), so the guard lives
in `skills/web-drift/SKILL.md` Step 7 (Apply) as a fenced shell check, run
against whichever repo a FIX would target.

## Run table

| # | Action | Result |
|---|---|---|
| 1 | `bash tests/test-web-drift-refusal-guard.sh` | 7/7 passed |
| 2 | extracted the guard's exact `test -f _meta/BACKLOG.md ...` line from the shipped SKILL.md and ran it against a real temp repo WITH `_meta/BACKLOG.md` | exit 0, no REFUSE line |
| 3 | same guard line against a temp repo with NO `_meta/BACKLOG.md` (negative control) | exit 1, `REFUSE: ... bin/board init ...` |

## Why extraction, not a lib test

web-drift ships no executable script (`lib/webcheck/` covers Tier 1 probing
only; Apply is agent-followed prose). Grepping the doc's prose would only
prove the WORDS are present, not that the shell logic those words describe
actually branches correctly. The test instead extracts the real fenced-code
guard line via `awk` and `eval`s it against two real temp directories, so a
future edit that breaks the guard's actual bash (while leaving the prose
plausible-looking) fails the test.

## Decision note

No local ledger fallback: a second, skill-owned source of truth for open
FIX rows is the same drift class the audit-loop's closing-evidence rule
exists to prevent (a row that closes nowhere is unfalsifiable). A boardless
consumer's fix is `bin/board init`, a decision that repo's owner makes, not
one web-drift works around silently.
