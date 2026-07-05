# Implementation notes: SPEC-146 (cockpit board command)

Delta from the spec only; decisions/tradeoffs the spec did not pin down, or found during build.

## 2026-07-05 09:00 No `bin/` entry point

**Context:** the goal file offered "`lib/board/board.sh` + `bin/board`, or extend the existing dispatch
(match whatever pattern the kit already uses)."

**Decision:** no `bin/` directory. The kit has ZERO `bin/` anywhere; every `lib/*.sh` (backlog.sh,
weekend-batch.sh, mega-merge.sh, gate-ledger.sh, ...) is invoked directly as `bash lib/<name>.sh
<subcommand>`. Adding a `bin/board` wrapper would be the first `bin/` entry in the whole repo and
would deviate from an established, repo-wide convention with no local justification.

**Why:** "match whatever pattern the kit already uses" is explicit in the goal text; the kit's
pattern is direct invocation, not a `bin/` layer.

**Impact:** `board.sh` is called as `bash lib/board/board.sh <cmd> ...` everywhere (README, the shim
design, tests), consistent with every sibling `lib/*.sh`.

## 2026-07-05 10:40 bash 3.2 compatibility: no negative array indices

**Context:** `_canon_path()`'s lexical `..`-resolution originally used `unset 'stack[-1]'` to pop
the last path component.

**Found:** negative array indices (`arr[-1]`) are a bash 4.3+ feature. macOS ships bash 3.2 as
`/bin/bash`, and `lib/goal/mega-merge.sh`'s own comments already flag "bash 3.2 on the macos-latest CI
runner" as a real, previously-bitten hazard (its `_merge_exclusion`/`mark` functions carry
`set -u`-safe empty-array guards for exactly this runner).

**Fix:** replaced with a positive-index `unset "stack[$((${#stack[@]}-1))]"`, verified directly
under `/bin/bash` (3.2.57) on this machine, not just the PATH-resolved (5.3) `bash`.

**Impact:** `lib/board/parse-board.sh`'s `_canon_path` is bash-3.2-safe; confirmed by running
`tests/test-board.sh`'s full 45-assertion suite under both `/bin/bash` and the PATH `bash`.

## 2026-07-05 11:15 repo_root canonicalization bug (found by the test suite itself)

**Found:** `pb_queue_rows` canonicalized the JOINED path (`repo_root/pointer`) via `_canon_path`
but compared the result against the RAW, non-canonicalized `repo_root` as a string prefix. On
this machine, `mktemp -d "${TMPDIR:-/tmp}/..."` produces a path with a double slash (`$TMPDIR`
itself ends in `/` here, a common macOS shape: `/var/folders/.../T/`), so `repo_root` as
originally passed in test fixtures carried `.../T//dk-board-test.XXXXXX`. `_canon_path` correctly
collapsed the double slash in the JOINED path, but the prefix check compared against the
UN-collapsed `repo_root`, so a legitimately in-bounds pointer (e.g.
`_meta/megagoals/mg1/goals/g1.md`) failed the containment check on a pure string mismatch and was
wrongly skipped as "outside allow-listed dirs."

**Fix:** `pb_queue_rows` now canonicalizes its own `repo_root` parameter as its first statement,
before using it anywhere (prefix checks AND the emitted repo-root column).

**Why this matters beyond the test fixture:** any real consumer whose `--repo-root` or
`REPO_ROOT` value contains a trailing slash, a `./`, or any other non-canonical form would have
hit the exact same false-negative in production. This was NOT a test-only bug.

**Impact:** caught live by `tests/test-board.sh`'s AC1/AC2 assertions (initially 4 failures on
first run), root-caused, fixed, all 45 assertions green after. No spec change needed (AC1/AC2
already specified "resolves to the real canonical pointer file"; the bug was purely in meeting
that criterion, not in the criterion itself).

## 2026-07-05 11:40 shellcheck: two warnings, both fixed rather than suppressed

- SC2034 (`OPT_DRY_RUN` appeared unused): rather than suppress, gave `--dry-run` an actual
  (documented) effect -- a stderr note that it is currently a no-op -- so the flag is genuinely
  read, not dead code accepted for a future that may never come.
- SC2195 (`*/../*|*/..` -- the second alternative can never match): the pointer string is always
  wrapped as `"/$pointer/"` before the case match, so it always ends in `/` and can never
  literally end in `..`; removed the dead alternative, added a comment explaining why the single
  `*/../*` pattern already covers every position (leading/interior/trailing `..`).

**Impact:** `shellcheck lib/board/board.sh lib/board/parse-board.sh tests/test-board.sh` exits 0 clean.
