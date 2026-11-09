# spec-status-machine: implementation notes

Brief: `docs/briefs/DECISION-BRIEF-declared-state-machines.md`. Shape copied from `lib/board/states.tsv`. This file is the delta only.

## Decisions not in the brief

- `get` has two non-state answers. `NONE` means no header (also an empty, missing or unreadable file). `UNKNOWN` means a header whose first word is not declared, or an empty value. A reader never sees a raw word.
- "Open" is `class != terminal`, and `UNKNOWN` is open. Before this change every reader treated any word other than SHIPPED or PARKED as open, so an undeclared word stays open.
- `live [--none live|dead] <files>` is the fifth verb. Four readers need a yes/no over many files, and context-readiness needs it in one pass (a fork per spec cost about 2s at SessionStart). Output is the open files, in argument order.
- The header is the FIRST `Status:` or `**Status:**` line (any case, no indentation). The old context-readiness and the greps closed a spec when ANY later line said shipped or parked. The first line decides now. One test case in `tests/test-hooks.sh` pinned the old rule (a late `Status: parked` closing a spec); it now pins the new one. No real spec has a second header line that disagrees with its first.
- The first word is `[A-Za-z][A-Za-z-]*`, so `VALIDATED,`, `Draft·2026`, `SHIPPED-PENDING` and `IMPLEMENTED, pending merge` all read. `SHIPPED pending merge` reads as SHIPPED, as the old prefix match did.
- Without `lib/` the hooks degrade to "every spec is open" (drift-guard, both compact hooks) or "no spec" (context-readiness). Hooks already tolerate a missing `lib/telemetry` the same way.
- `spec-index` prints the canonical state in its Status column, `UNKNOWN` for an undeclared word, `(none)` for no header. It no longer prints the raw decorated text. This is the one printed-output change.
- `goal-drafts.sh` changed only `spec_is_shipped` (about line 94). The archive and list code is another worker's.
- `PARKED` is `terminal`, not `hold` as on the board: a parked spec is skipped by every reader, which matches today's behavior.

## NONE behavior, per reader (kept as it was)

| Reader | A spec with no header is |
|---|---|
| context-readiness | not open (`--none dead`) |
| spec-drift-guard | open (`--none live`) |
| pre-compact-backup | open (`--none live`) |
| post-compact-reinject | open (`--none live`) |
| spec-index | shown as `(none)` |
| goal-drafts | not shipped |

## Live-spec counts on the real docs/specs (325 spec files)

| Reader | Before | After | Why |
|---|---|---|---|
| context-readiness | 181 | 240 | the bold `**Status:**` specs now read (a bold SUPERSEDED closes) |
| spec-drift-guard, pre-compact-backup, post-compact-reinject | 242 | 241 | bold SUPERSEDED (an alias of PARKED) is closed now |
| goal-drafts (SHIPPED) | 81 | 81 | no real spec is bold SHIPPED yet |
| spec-index rows showing `(none)` | 61 | 1 | bold headers read; the one left has no header |

The 240 and 241 differ by exactly the one header-less spec. Both compact hooks pick the same spec before and after.

## Left as is, with the reason

- `lib/precedent/inventory.py` reads a `status =` key from tool metadata, not a spec header.
- `commands/*.md` and `docs/specs/*.md` still spell the states in prose and a few `Status:` examples. Prose lists them legitimately; the copy detector scans `hooks/`, `lib/` and `bin/` code only.

## Open questions for the operator

- Should a new spec header ever be written bold? The reader accepts both. I did not touch `commands/*.md`, so any template there is unchanged.
- The legacy words (BUILT, IMPLEMENTED, REVIEWED, READY, SHIPPED-PENDING, SUPERSEDED) stay in stored specs. A later pass can rewrite them if you want the aliases gone.
