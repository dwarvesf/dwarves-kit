# Verification -- board-only-inert

`proof-ledger.sh classify` now returns inert when every COMMITTED path in base..HEAD is a board file (`_meta/BACKLOG.md`, `BACKLOG.md`, `_meta/archive/BACKLOG*.md`), so a board flip owes no proof and no override.

## Change

- Root cause: `classify()` reads `_changed`, which adds working-tree and untracked paths to the committed diff. A shared checkout with one unrelated dirty file (a modified `.pdf`) made a board-only push behavioral. dfoundation needed about 12 manual overrides in one day for this.
- Fix: a `board-only` block at the top of `classify()` reads `git diff base..HEAD` alone. All paths board files returns inert. Any other path, an empty diff, or an unreadable base skips the block and keeps today's rules.
- `proof-gate.sh class "<task text>"` (task-description classifier) is not changed. The ship gate never calls it for the push decision.

## Green run

```
Command: bash tests/test-proof-board-only-inert.sh
Exit: 0
Output:
PASS board-only commit, clean tree -> inert
PASS board-only commit: check owes nothing (rc) -> 0
PASS board-only commit, unrelated dirty pdf -> inert
PASS board-only commit + dirty pdf: check rc -> 0
PASS board-only commit, dirty code (not shipped by the push) -> inert
PASS board + lib/y.sh commit -> behavioral
PASS board + code: check still blocks (rc) -> 1
PASS board + _meta/board wrapper (no extension) -> behavioral
PASS _meta/archive/BACKLOG-tool.sh is not a board file -> behavioral
PASS board + docs/BACKLOG.md + lib/BACKLOG.md (lookalikes, still .md) -> inert
PASS empty diff, clean tree -> inert
PASS empty committed diff, dirty code -> behavioral
PASS unreadable base ref, dirty code -> behavioral
PASS block-stripped lib on board-only + dirty pdf (the bug; block is load-bearing) -> behavioral
ALL PASS
Verdict: PASS
```

Real hook, same fixture (a clone of dfoundation, one board-row commit, `sales/deals/loft/pitch/decision-deck.pdf` dirty):

| Hook | Command | Exit | Verdict |
|---|---|---|---|
| before (master kit) | `ship-gate.sh` fed `git push -u origin chore/board-sim` | 2, `BLOCKED: proof of done. This is a 'behavioral' change` | the bug |
| after (this branch, `CLAUDE_PLUGIN_ROOT` at the worktree) | same input | 0 | PASS |

Adjacent suites (`bash tests/run-all.sh --only <pattern>`): `proof` 14 of 14 ok, `ship-gate` 8 of 8 ok, `classify` 4 of 4 ok, `mega` 7 of 7 ok; `run-all.sh --changed` 48 of 48 ok. `feature-registry.sh check docs/FEATURES.md` reports fresh.

## Negative control

```
Command: bash lib/gate/proof-ledger.sh negctl "$PWD" "bash tests/test-proof-board-only-inert.sh" "sed -i '' '/board-only: begin/,/board-only: end/d' lib/gate/proof-ledger.sh"
Exit: 1 (under mutation, RED expected)
Output:
Mutation: sed -i '' '/board-only: begin/,/board-only: end/d' lib/gate/proof-ledger.sh
Changed: lib/gate/proof-ledger.sh
FAILS: 3
Restore: git checkout HEAD -- lib/gate/proof-ledger.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The three failures are the dirty-pdf classify, the dirty-pdf check, and the dirty-code classify cases. The block is load-bearing.

## Reproduce

```bash
bash tests/test-proof-board-only-inert.sh
bash lib/gate/proof-ledger.sh negctl "$PWD" "bash tests/test-proof-board-only-inert.sh" "sed -i '' '/board-only: begin/,/board-only: end/d' lib/gate/proof-ledger.sh"
```

## Not proven

- The board file set is fixed paths, not read from a repo's board wrapper. A repo whose wrapper points at another file gets no benefit (a `.md` file is already inert when the checkout is clean).
- A board commit that also flips a non-board path in the same push stays behavioral by design.
- Task-description classification (`proof-gate.sh class "chore(board): ..."` prints `behavioral`) is unchanged.
