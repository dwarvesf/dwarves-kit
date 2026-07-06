# Sub-goal 05: stable-interface

**Merge policy:** auto
**Time budget:** 3-5 hours
**Proof:** run-table showing a consumer driving the harness through the STABLE entrypoint (not a deep lib path) + the board still works. Rung 2 + a negative control (an internal lib reorg does not break the consumer call).
**Design:** bearing
**Depends on:** 04
Model: opus
**Branch:** feat/harness-ops-05-interface
**PR base:** main

## Outcome

Consumers stop reaching `$DWARVES_KIT/lib/<subsystem>/<file>.sh` deep paths (the exact thing that silently broke `_meta/board` when the lib regroup moved `board.sh`). There is ONE stable entrypoint , a `kit <subsystem> <verb>` dispatcher OR the installed per-subsystem commands (`board`, ...) , that the adopt contract points at, so an internal lib reorg never breaks a consumer again. The temporary board-shim patch (repointed to `lib/board/board.sh`) is replaced by the stable form.

## Design

Design-bearing (2 approaches: a thin `kit` dispatcher vs installed per-subsystem command shims). Pick by fit and record in the spec's `## Design`; link the config brief's "stable consumer interface" open question. Whichever wins, the invariant is: consumers reference the stable name, never a deep lib path.

## How to close the loop

- Enumerate every consumer reach into `$DWARVES_KIT/lib/...` (grep across ops-toolkit + the adopt-injected CLAUDE.md block); confirm they'd break on a lib move.
- Build the stable entrypoint (dispatcher or installed commands); repoint the adopt contract (`lib/adopt.sh`'s CLAUDE.md block + WORKFLOW/AGENTS pointers) to it.
- **Cross-track overlap (advisor P5 #2):** `lib/adopt.sh:72-83` (the WORKFLOW pointer text) is ALSO edited by Track B's 12-root-slim (which repoints it to the new docs/ bulk). These two touch the SAME lines. This sub-goal (05) must land BEFORE 12, OR whichever merges second does a mandatory rebase + manual reconcile of that block (auto-bottom-up merge does NOT detect file-level cross-track overlap). Coordinate: 05 references the stable entrypoint; 12 references the docs/ bulk location; the final adopt.sh block must carry BOTH.
- Repoint `_meta/board` / `board-all` (and any other consumer shim) to the stable form.
- Test (negative control): rename an internal lib file, assert the consumer call still resolves via the stable entrypoint. Capture the run-table.

**Done =** consumers drive the harness through a stable entrypoint (no deep lib paths), verified by a run-table where an internal lib rename does NOT break the consumer call; the board works through the stable form.

**Kit-adopted repo? Record the gates** (dwarves-kit cwd, `lane-classify` → full; touches adopt).

## Handoff on completion

Flip ROADMAP `[x]` + PR #; HANDOFF.md → 06/07; append DECISIONS.md; report; EXIT.

## Scope edges

**In:** the stable entrypoint, the adopt contract's pointers, consumer shims.
**Out:** the subsystems' internal logic, the resolver.
**Not:** rewriting every lib caller, removing the internal lib structure, a CLI framework.

## PR body

Adds a stable consumer entrypoint (`kit <sub> <verb>` / installed commands) so consumers stop referencing deep `$DWARVES_KIT/lib/...` paths (the board-break class of bug); repoints the adopt contract + board shims. Verify: the lib-rename-doesn't-break-consumer run-table. Part of `harness-ops` (Track A), see ROADMAP.md.

## Notes
