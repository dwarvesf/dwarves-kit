# SPEC-146: the cockpit board command (`lib/board/board.sh` + `lib/board/parse-board.sh`)

Status: SHIPPED
Lane: full
Backlog: runner-fastpath sub-goal 04 (ops-toolkit `_meta/megagoals/runner-fastpath/goals/04-board-queue.md`)
Branch: feat/board-tool
Relates-to: SPEC-055 (backlog kanban, the base renderer this delegates to), the runner-fastpath
mega-goal (ops-toolkit `research/2026-07-04-board-hermes-bridge-design.md`, 2026-07-05 amendment),
sub-goal 03K (`feat/orchestrate-queue`, the queue's consumer), sub-goals 07/08 (board-bridge
mirror/writeback, future consumers of `lib/board/parse-board.sh`)

## Problem

Han's cross-repo cockpit (13 repos' `BACKLOG.md` boards) was rendered by two hand-maintained
bash scripts living in the ops-toolkit consumer repo: `_meta/board` (single-repo kanban + a
`priority` urgency/fit quadrant) and `_meta/board-all` (a `boards.txt` registry walk + a
`priority matrix` cross-repo pivot). Both scripts duplicated real render logic (an awk quadrant
program, a registry-walk loop) that belonged in the generic kit, not in a personal consumer repo,
and neither had a machine-readable "this row feeds an unattended runner" grammar for the
runner-fastpath mega-goal's overnight queue (sub-goal 03K).

## Solution shape

`dwarves-kit` gains the `board` command as the SOLE cockpit board tool. It is GENERIC and
config-driven: the kit carries no personal data (no hardcoded registry, no hardcoded repo list);
the consumer's `boards.txt` registry and repo root are read at runtime via `--repo-root <path>` /
the `REPO_ROOT` env var, the kit's existing consumer-config pattern (`lib/queue/weekend-batch.sh`'s
`--repo-root`, `lib/goal/mega-merge.sh`'s env-override precedent).

1. **`lib/board/board.sh`**: single-repo (`board|next|set|states|priority [mode]`, `--backlog-file`)
   and cross-repo (`all <cmd>`, `--repo-root`/`--registry`) render, migrated VERBATIM from
   ops-toolkit's `_meta/board`/`_meta/board-all` (the `priority` quadrant awk + the
   `priority matrix` pivot are copied unchanged, parameterized only by file/registry path).
   Base kanban render (`board`/`next`/`set`/`states`) is UNCHANGED behavior: it always shells out
   to the existing `lib/board/backlog.sh`, never reimplements it.
2. **`lib/board/parse-board.sh`**: a new, reusable structured parser. `pb_rows` is a public superset of
   `backlog.sh`'s private `_rows()` (adds the full row text so a caller can read inline tags).
   `pb_queue_rows` extracts and ALLOW-LISTS `#queue{repo=<name>,pointer=<path>}` tokens on
   `queued` rows (see `## Design` below for the full security model).
3. **`board.sh queue [--dry-run]`**: walks the consumer `boards.txt`, calls `parse-board.sh
   queue-rows` per registered repo, and emits `slug<TAB>repo-path<TAB>pointer-path` on stdout for
   every allow-listed token (`slug` = `<repo-name>__<ID>`, globally unique even where `ID-NNN`
   prefixes collide across repos). Never mutates any `BACKLOG.md`; `--dry-run` is accepted as
   forward-compat surface for a future write-capable extension, documented as a no-op today.

The ops-toolkit shims (`_meta/board`, `_meta/board-all`) shrink to one-line `exec`s of this
command (shim content delivered to the conductor; this repo does not touch ops-toolkit).

## Design

**New command surface + security model, so this is design-bearing (ADR-0031 §1).**

- **Why a new marker grammar instead of reusing the existing `#u-hi`/`#f-hi` tag convention?**
  Those tags are single atoms (`#u-hi`); a queue token needs two associated fields (repo +
  pointer) that must travel together. `#queue{repo=<name>,pointer=<path>}` uses `{}`+`key=value`
  pairs (not `:` as a separator, to avoid ambiguity with a path that could theoretically contain
  one; not bare positional fields, so a future 3rd key is additive and forward-compatible).
- **Why validate BEFORE checking repo self-consistency, not after?** The charset gate (step 1)
  is the FIRST wall: a malformed field can never survive far enough to reach the semantically
  richer checks, so even a bug in the later logic could not turn a rejected value into an
  accepted one. Defense in depth, cheapest check first.
- **Why re-canonicalize `repo_root` inside `pb_queue_rows`, not just the joined path?** A real
  bug caught during this build: macOS's `$TMPDIR` commonly ends in a trailing slash, so a
  caller-supplied repo-root can contain a double slash. Canonicalizing only the JOINED path
  (`repo_root/pointer`) while comparing against a non-canonical `repo_root` prefix made a
  legitimately in-bounds pointer fail on a pure STRING mismatch. Fixed by canonicalizing
  `repo_root` itself as the function's first step; caught by the test suite (recorded here as the
  implementation-notes entry, not restated in full).
- **Why is `queue` never a hard error, only a per-row skip?** A free-text Notes cell across 13
  repos will inevitably contain typos, stale pointers, and drafts. A single bad row must never
  take down the whole feed for every other repo; "skip + logged reason, count and report" is the
  only posture that scales to that reality.
- **Why accept `--dry-run` when `queue` never mutates anything?** Symmetry with a plausible
  future write-capable verb (e.g. flipping a picked row to `claimed`) and with the sibling
  `board-bridge` design's `mirror`/`writeback` verbs (SG-07/08), which WILL mutate. Accepting and
  documenting the flag now costs nothing and avoids an "unknown flag" error if a caller
  (03K) passes it defensively.

## Acceptance criteria

- AC1: `lib/board/parse-board.sh` extracts a valid `#queue{repo=...,pointer=...}` token on a `queued`
  row and resolves it to a real, existing, allow-listed absolute path.
- AC2: A malformed token (missing a required key) is skipped, never emitted.
- AC3: A token on a NON-`queued` row is silently out of scope (not an error).
- AC4: Single-repo `board|next|set|states|priority` and cross-repo
  `all board|next|states|priority [overview|matrix]` render correctly on a fixture registry.
- AC5 (NC-a): zero tokens across a registry -> `queue` emits nothing on stdout, reports "0 rows"
  on stderr, exits 0.
- AC6 (NC-b): a token whose declared repo does not match the repo whose board it lives in (a
  cross-repo spoof, including a repo name absent from `boards.txt` entirely) is skipped with a
  reason naming the mismatch.
- AC7 (NC-c): a pointer that resolves outside `_meta/megagoals/**` or `.claude/goals/**` --
  including via `../` traversal -- is skipped with a reason; a dangling (non-existent) pointer is
  also skipped (defense in depth).
- AC8 (NC-d): a shell-metachar-laden field is charset-rejected before it can reach any exec
  boundary; a static source audit confirms neither `lib/board/board.sh` nor `lib/board/parse-board.sh` ever
  `eval`s or `sh -c`'s a parsed value.
- AC9 (NC-e): **RENDER NON-REGRESSION.** `board`/`next`/`priority [overview|matrix]`/`states`,
  invoked exactly as the ops-toolkit shims would invoke them, are byte-identical to the
  pre-migration `_meta/board`/`_meta/board-all` output, checked against the REAL ops-toolkit
  cockpit (13 registered repos). This is the load-bearing proof: a regression here breaks the
  operator's daily-use cockpit tool.

## Test plan

| # | Case | Proof |
|---|---|---|
| 1 | AC1-AC4 (parser + render fixtures) | `tests/test-board.sh` AC1/AC2, AC3, AC4, AC5, AC6 sections |
| 2 | NC-a zero tokens | `tests/test-board.sh` "NC-a" section |
| 3 | NC-b repo mismatch / not registered | `tests/test-board.sh` "NC-b" section |
| 4 | NC-c traversal + wrong-dir + dangling pointer | `tests/test-board.sh` "NC-c" section |
| 5 | NC-d shell-metachar (dynamic canary + static source audit) | `tests/test-board.sh` "NC-d" section |
| 6 | NC-e render non-regression (13-repo real cockpit, 9 command pairs) | `tests/test-board.sh` "NC-e" section (SKIPS in CI where ops-toolkit is absent, same precedent as `test-weekend-batch.sh`) |
| 7 | Negative control (load-bearing, confirmed RED then reverted) | see `docs/verification/board-tool/proof-of-done.md` |
| 8 | No regression to sibling suites | `bash tests/test-meta.sh`, `bash tests/test-hooks.sh` |
| 9 | Live `board queue --dry-run` against the real ops-toolkit cockpit, read-only | see proof-of-done.md |

## Rollback

`git revert`. Two new `lib/` files + one new `tests/` file + doc mentions (README, architecture,
a `tests/test-meta.sh` pin) + a CI step; no daemon, no external state, no change to
`lib/board/backlog.sh`. The ops-toolkit shim swap is a SEPARATE change in a separate repo (delivered as
content, not committed here), so reverting this PR alone leaves ops-toolkit's existing
`_meta/board`/`_meta/board-all` scripts working exactly as they do today (they were never
touched).
