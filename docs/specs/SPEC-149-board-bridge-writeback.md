# SPEC-149: board-bridge writeback (`board.sh writeback`, `lib/board-writeback.sh`)

Status: SHIPPED (code + tests); the resulting PR is HELD for operator review, never auto-merged
Lane: full
Backlog: runner-fastpath sub-goal 08 (ops-toolkit `_meta/megagoals/runner-fastpath/goals/08-bridge-writeback.md`)
Branch: feat/board-writeback
Relates-to: SPEC-147 (the read-mirror leg this consumes: the NDJSON snapshot + `row_hash`
conflict-rule input), SPEC-146 (the cockpit board command + `lib/parse-board.sh`), ops-toolkit
`research/2026-07-04-board-hermes-bridge-design.md` (the binding design source, "Two-way without
the graveyard" section + its 2026-07-05 amendment)

## Problem

SPEC-147 built the P0 read-mirror leg: git -> Hermes, one-way, zero writeback risk. That leaves
the actual ergonomic win on the table: Han moves a card on his phone/Hermes UI and it just sits
there, disconnected from the git SoT, until he remembers to hand-edit the BACKLOG.md too. This
sub-goal builds the P1 writeback leg, an agent-driven channel writing INTO the git source of
truth, which is exactly why it is merge-policy `gate`: the operator reviews and merges every sync
PR by hand. This is the whole reason blind two-way sync is a known graveyard and why this design
insists on one writer per direction, a hash-keyed conflict rule, and a HELD PR rather than a
direct commit to any default branch.

## Solution shape

`lib/board.sh` gains a `writeback` subcommand, backed by a new file, `lib/board-writeback.sh`,
which SOURCES `lib/board-mirror.sh` (function-level reuse, not a re-fork -- the same discipline
`board-mirror.sh` itself uses for `lib/parse-board.sh`).

1. **Diff**: `lib/board-writeback.sh diff` reads each opted-in repo's live Hermes board (ONE
   batched `hermes kanban --board <b> list --json` call per board, not per row) and the SPEC-147
   mirror snapshot, and emits a validated NDJSON changeset of rows whose live Hermes status
   differs from what the snapshot recorded at mirror time.
2. **Validate** (per row, independently -- one row's rejection never aborts the run): the row's
   repo must still be opted in (`bridge=on` in the registry -- re-checked here, defense in depth
   on top of the mirror's own filter, since a snapshot can outlive a registry edit); the live
   Hermes status must reverse-map to a LEGAL `backlog.sh` state; the row's CURRENT git-side content
   hash must still equal the value the snapshot recorded (the CONFLICT RULE -- git wins, always).
   A missing or corrupt snapshot REFUSES the entire run (explicit error, nonzero exit), never
   degrading to "no conflicts found, apply everything".
3. **Apply**: `lib/board-writeback.sh apply` builds a fresh `chore/board-sync` branch in an
   ISOLATED `git worktree` off the CURRENT HEAD (never the caller's own checkout, never a cached
   ref), edits ONLY the Status column of the matched rows (reusing `lib/backlog.sh`'s own `set`),
   commits with `actor=hermes` in the body, pushes, and opens the sync PR via `gh pr create`
   (argv-only; never auto-merged). Snapshot refresh after a successful apply updates only
   `hermes_status` (see `## Design`'s "Snapshot refresh" subsection for why `row_hash` stays
   untouched).

v1 scope (per the sub-goal contract): STATUS MOVES ONLY, BACKLOG.md rows only (mega-goal cards,
new-card writeback, and note edits are explicitly out; see `## Scope edges`).

## Design

### Reverse state mapping (the lossy collapse, documented and accepted)

SPEC-147's forward map (`_target_native`) is many-to-one: `claimed`/`speccing`/`validated`/
`executing` all collapse onto Hermes's `ready`. The reverse cannot recover the original nuance --
this is inherent to the mirror's own reachable-state finding (only `{triage, ready, blocked,
done}` are durably reachable in Hermes v0.18.0; see SPEC-147's Design block), not a new limitation
this sub-goal introduces.

| Hermes live status | git target status | Rationale |
|---|---|---|
| `triage` | `queued` | The exact inverse; 1:1 on the forward map too. |
| `ready` | `claimed` | The honest nearest-available "picked up" state. NOT speccing/validated/executing -- writeback cannot know which of those four the operator "meant" when they moved a card to `ready`, and `claimed` is the least presumptuous of the four (a signal, not a claim of full status fidelity). |
| `blocked` | `parked` | The exact inverse; 1:1 on the forward map too. |
| `done` | `shipped` | The safe default over `dropped`: a card marked done in Hermes reads as "finished", not "abandoned". `dropped` has no writeback path in v1. |
| `todo`, `running`, or any other value | REJECTED (no legal mapping) | Neither is ever a write-target in the forward direction either (SPEC-147's Hermes-CLI-reality finding); seeing one live implies either a manual out-of-band Hermes edit or an untested future CLI/version change. Writeback must not guess -- it refuses that ONE row (not the whole run) with a named reason. |

### The conflict rule (load-bearing)

A Hermes-side edit applies ONLY if the row's CURRENT git-side content hash (recomputed fresh via
`board-mirror.sh`'s `extract_rows`, sourced, not re-forked) still equals the value the mirror
snapshot recorded for that origin. Any mismatch -- someone edited the row's item/notes/status on
git since the last mirror, independent of the Hermes-side move -- SKIPS that row, reports why, and
leaves the file untouched; the row heals naturally on the NEXT `board mirror` run (mirror's own
diff will see the new git content and post a comment to Hermes, same as any other content change).
Git wins, always; this is the whole reason the design exists.

### Why a worktree, not the caller's own checkout

The operator's real BACKLOG.md checkout must never be silently switched to a `chore/board-sync`
branch mid-session. `apply` builds the sync branch via `git -C <repo_root> worktree add -B
<branch> <scratch-dir> HEAD` -- resolved fresh, right there, never a cached/stale ref -- edits,
commits, and pushes INSIDE the scratch worktree, then removes it. `repo_root`'s own working
directory and current branch are never touched. This also happens to be exactly what keeps a
concurrent append-only writer's row safe (NC6): whatever HEAD is at the instant `apply` runs
already carries any row appended after the mirror snapshot was taken, and the sync branch is built
ON TOP of that HEAD.

### Snapshot refresh (the subtlety this design turns on)

After a successful apply, ONLY `hermes_status` is updated in the snapshot -- to the live value
writeback just observed. `row_hash` is passed through UNCHANGED. This is deliberate, not an
oversight, and follows directly from the PR being HELD:

- The writeback commit lands on an unmerged `chore/board-sync` branch. The actual git SoT (the
  default branch the next `board mirror` run reads) has NOT changed yet.
- Refreshing `hermes_status` stops writeback from re-diffing (and re-PR-ing) the SAME Hermes-side
  move on a second run before the PR merges -- a `board writeback` run made twice in a row on an
  unmerged PR reports "0 changes" the second time, not a duplicate PR.
- Leaving `row_hash` untouched keeps `board mirror`'s own idempotence correct: mirror compares the
  CURRENT git extract's hash against the snapshot's row_hash, which still (correctly) reflects the
  not-yet-merged git content, so mirror does not think anything changed until the PR actually
  merges. At that point mirror's ordinary CHANGE path fires once (posts a Hermes comment noting
  the new content) and upserts the row_hash itself -- self-healing, no special-case code needed.

**Known limitation (documented, not fixed here; explicitly out of scope per the contract's "Not"
list)**: if the operator instead CLOSES the held PR without merging, the snapshot has already
"forgotten" the delta (its `hermes_status` now matches the live value), so writeback will not
re-propose it. Recovery requires moving the Hermes card again (any further live-status change
re-triggers a fresh diff). This is a genuine gap in the v1 design, traded off against NOT building
a bidirectional reconciliation surface beyond the hash rule (explicitly out of scope).

### Changeset format (internal, NDJSON, one object per validated row)

```json
{"origin":"ops-toolkit:ID-042","repo":"ops-toolkit","id":"ID-042","hermes_id":"t_...",
 "board":"ops-toolkit","backlog_file":"/abs/path/_meta/BACKLOG.md","repo_root":"/abs/path",
 "current_status":"queued","target_status":"claimed","hermes_status":"ready",
 "row_hash":"<sha256, PASSED THROUGH from the snapshot, unchanged>"}
```

### A real portability bug this build's own smoke test caught

`_repo_root_for` (sourced from `board-mirror.sh`) resolves a repo root via `git rev-parse
--show-toplevel`, which git ALWAYS returns as a physical path (symlinks resolved). On macOS,
`$TMPDIR` (and therefore any fixture's registry path, and the real ops-toolkit checkout if it ever
sits under a symlinked mount) resolves through the `/var -> /private/var` symlink. A registry's
literal `path` column is NOT canonicalized the same way, so `repo_root` (physical) and
`backlog_file` (logical, symlink intact) silently diverged, breaking `_apply_group`'s
`rel="${backlog_file#"$repo_root"/}"` string-prefix strip (the prefix simply never matched, and
`rel` fell back to the whole absolute path, producing a nonsensical in-worktree file path).
**Fix**: `diff` canonicalizes the registry's `path` via `pwd -P` (physical) immediately after
resolving `~`, before it is ever compared against a `repo_root` value. Caught live, before this
ever reached the automated suite, by manually driving the tool end-to-end against a real macOS
tmp path -- exactly the kind of bug a purely-in-process unit test with mocked paths would have
missed.

## Acceptance criteria

- AC1: `reverse-native` maps every reachable Hermes status (`triage/ready/blocked/done`) to its
  correct git target, and rejects any other value (`todo`, `running`, or an arbitrary custom
  status) with a nonzero exit and empty output.
- AC2: a genuine Hermes-side status move (live status differs from the snapshot's recorded
  `hermes_status`) produces exactly the right changeset entry; a row with no Hermes-side move
  produces none, and only ONE Hermes call is made per board (batched, not per-row).
- AC3: `apply` builds the sync branch in an ISOLATED `git worktree`; the caller's own checkout
  stays on its original branch, at its original HEAD, with a clean working tree, throughout.
- AC4: the sync commit's body carries `actor=hermes` on its own line.
- AC5: snapshot refresh after a successful apply updates ONLY `hermes_status`; `row_hash` passes
  through unchanged (see `## Design`'s "Snapshot refresh" subsection).
- AC6 (NC1, LOAD-BEARING): a hash mismatch (the git row changed since the last mirror,
  independent of any Hermes-side move) SKIPS that row, reports why, and leaves the file untouched.
- AC7 (NC2): an illegal target status (a live Hermes status with no legal `backlog.sh` mapping)
  is rejected with a named reason; the file is untouched.
- AC8 (NC3): an empty changeset (no Hermes-side moves at all, or a second run before any further
  Hermes-side move) produces zero commits, zero branches, and an honest "0 changes" line.
- AC9 (NC4): a card whose origin's repo is NOT currently opted in (absent from the registry, or
  `bridge` != `on`) is refused with a named reason; the repo's Hermes board is NEVER queried at
  all (defense in depth on top of the mirror's own opt-in filter, since a snapshot can outlive a
  registry edit).
- AC10 (NC5, LOAD-BEARING): a missing OR corrupt mirror snapshot REFUSES ALL edits -- an explicit
  error, a nonzero exit, and (in the `board writeback` wrapper) zero downstream git/Hermes calls.
  A present-but-EMPTY snapshot (a real, valid "zero rows mirrored yet" state) is NOT treated as
  corrupt: it produces an honest "0 changes", exit 0.
- AC11 (NC6, LOAD-BEARING): a row appended to the fixture BACKLOG.md AFTER the mirror snapshot was
  taken (simulating a concurrent append-only writer) survives BYTE-FOR-BYTE on the sync branch;
  the sync branch's parent commit equals the pre-writeback HEAD (built from the CURRENT HEAD, not
  a stale/cached one).
- AC12 (rung-4 red-team, SECURITY): no card-text field (item/notes) ever reaches the commit
  message, the PR title/body, or any `gh`/`git` argv element -- only IDs matched against
  `BACKLOG_ID_RE` and status keywords drawn from the closed `LEGAL_STATES`/native-status
  vocabularies. No `eval`/`sh -c` of any parsed variable anywhere in `lib/board-writeback.sh`.

## Test plan

| # | Case | Proof |
|---|---|---|
| 1 | AC1-AC5 (unit + integration fixtures, incl. a real local bare-remote push) | `tests/test-board-writeback.sh` AC1-AC5 sections |
| 2 | NC1 hash mismatch | `tests/test-board-writeback.sh` "NC1" section |
| 3 | NC2 illegal target status | `tests/test-board-writeback.sh` "NC2" section |
| 4 | NC3 empty changeset | `tests/test-board-writeback.sh` "NC3" section |
| 5 | NC4 non-opted-in repo in the Hermes delta | `tests/test-board-writeback.sh` "NC4" section |
| 6 | NC5 missing/corrupt/empty snapshot (3 sub-cases) | `tests/test-board-writeback.sh` "NC5" section |
| 7 | NC6 two-writer coexistence + branch-from-current-HEAD | `tests/test-board-writeback.sh` "NC6" section |
| 8 | Static security audit (no eval/sh-c, no direct DB access, discrete gh argv) | `tests/test-board-writeback.sh` final section |
| 9 | Round-trip demo (fixtures only): move one card, capture the branch+commit diff | proof-of-done.md "Round-trip demo" |
| 10 | Rung-4 red-team pass: force stale-hash / bypass missing-snapshot guard / bypass opted-in filter / argv-injection | proof-of-done.md "Rung-4 red-team pass" |
| 11 | No regression to sibling suites | `bash tests/test-board.sh`, `bash tests/test-board-mirror.sh`, `bash tests/test-meta.sh`, `bash tests/test-hooks.sh` |

## Scope edges

**In**: the `writeback` subcommand in `lib/board.sh` (thin dispatcher) + `lib/board-writeback.sh`
(the substantial diff/apply/PR logic), snapshot refresh, its docs/proof.

**Out** (explicitly, per the sub-goal contract): new-card writeback (a card born on Hermes gets no
git-side row in v1), note/content edits (only the Status column is ever touched), non-ops-toolkit
repos in the real deployment (the code itself is generic over the registry; only Han's actual
`boards.txt` opt-in is scoped to `ops-toolkit` for the first real run), Notion, cron.

**Not**: auto-merging the sync PRs (this tool NEVER merges; the operator does, by hand, after
review), bidirectional merge logic beyond the hash rule (see the "Known limitation" above),
editing anything in the BACKLOG.md-shaped file other than the Status column of matched rows,
Python, DuckDB.

## Rollback

`git revert`. Two new files (`lib/board-writeback.sh`, `tests/test-board-writeback.sh`), one new
`board.sh` dispatch case (`writeback`), a doc-impact map update, a CI step, and a `tests/test-meta.sh`
structural pin. No daemon, no external state change on any real Hermes instance or real repo (this
sub-goal's own live demos ran entirely against disposable, throwaway git fixtures + stubbed
`hermes`/`gh` binaries; the PR this sub-goal itself opens against `master` is the ONLY real,
non-fixture artifact it produces, and it is HELD, never merged, by contract). Reverting leaves
`board.sh mirror`/`status`/`queue`/`all`/single-repo render behavior byte-identical to before
(SPEC-147's own NC6 proof re-confirmed unaffected by this sub-goal, see proof-of-done.md).
