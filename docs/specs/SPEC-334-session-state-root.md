# Spec: session-state-save.sh resolves the repo root once, instead of trusting $PWD
Generated: 2026-09-28
Status: DRAFT
Lane: full

## Problem

`hooks/session-state-save.sh` (a Stop and SubagentStop hook, wired in `hooks/hooks.json`) sets:

```sh
STATE_DIR=".claude/session-state"
```

a path relative to the hook's `$PWD`. When a Claude Code session's cwd is a repo subdirectory
(observed: a session sitting in `ops-toolkit/.claude/handoffs/`), the hook writes a NESTED copy:
`ops-toolkit/.claude/handoffs/.claude/session-state/` (`last-state.md`, `.last-fingerprint`,
`archive/`), instead of the repo-root `.claude/session-state/` every other reader (crash
recovery, `start`, a human skimming the repo) expects.

The git calls inside the hook (`git branch --show-current`, `git status --porcelain`, `git diff
HEAD`, `git log --oneline -5`, `git rev-parse HEAD`, `git rev-parse --is-inside-work-tree`) all
resolve the repo correctly from any subdirectory, git climbs to find `.git` on its own. Only the
FILE PATH the hook writes to stays relative to `$PWD`. That mismatch is what masks the bug: the
hook still reports correct branch/commit/diff content, just under the wrong directory.

## Solution

Resolve the repo root once, at the top of the hook, and derive every `.claude/session-state/...`
path from it instead of from `$PWD` directly:

```sh
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
STATE_DIR="$ROOT/.claude/session-state"
```

`git rev-parse --show-toplevel` returns the WORKTREE's own root when run inside a git worktree
(not the main checkout's root), so a worktree session still keeps its own state directory,
unchanged from today's behavior. Outside a git work tree the command fails (non-zero) and the
`||` falls back to `$PWD`, matching the hook's existing fail-open contract: it still writes
somewhere and still exits 0.

### Why not use the hook's JSON input `.cwd` instead of `$PWD`

Some PreToolUse hooks in this repo (`board-row-gate.sh`, `context-budget.sh`) read `.cwd` from
the hook's JSON input because THEIR job is to reconstruct where a shell command would have run
after the command text itself does a `cd`/`pushd`/`-C` , the process's own `$PWD` at hook-execution
time is not the value they need. `session-state-save.sh` has no such indirection: it is a
Stop/SubagentStop hook, not wrapping a shell command, and it runs in the session's actual working
directory. Claude Code's hook input carries the SAME cwd Stop/SubagentStop hooks already execute
in, so `.cwd` and `$PWD` read the same value here. Reading `.cwd` would add a `jq` parse and an
`INPUT` dependency for no behavior change. Decision: keep using `$PWD` (via `git rev-parse
--show-toplevel`), do not switch to `.cwd`.

### Other hooks with the same shape (grepped)

`grep -n '"\.claude/` across `hooks/*.sh` `hooks/*.py`, excluding `show-toplevel` hits, finds
three relative-`.claude/`-path sites:

| Hook | Line | In scope? | Why |
|---|---|---|---|
| `hooks/session-state-save.sh` | `STATE_DIR=".claude/session-state"` | Yes | This spec's own fix. |
| `hooks/pre-compact-backup.sh` | `BACKUP_DIR=".claude/backups"` | **No** | Same relative-path shape (a PreCompact hook, same nested-dir risk from a subdirectory cwd), but a separate hook with its own file, its own tests (none observed touching it in this task), and its own fixture surface. Fixing it here would widen this branch past the one reported bug. Flagged for a follow-up fix using the identical `ROOT=$(git rev-parse --show-toplevel ...)` pattern. |
| `hooks/anti-rationalization.sh` | `if [ -d ".claude/debug" ]; then` | **No** | Different shape: a read-only existence CHECK gating a nested code path, not a directory this hook creates or writes into. Its own root-resolution question (should the debug-ledger check also anchor at the repo root) is a separate, narrower decision belonging to whoever owns the debug-ledger convention, not to this session-state fix. |

Neither excluded hook is touched by this branch.

## Task Breakdown

### Phase 1: Foundation
- [x] TASK-A: Write this spec.

### Phase 2: Core
- [ ] TASK-B: In `hooks/session-state-save.sh`, replace the relative `STATE_DIR="..."` line
  with the `ROOT="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"` /
  `STATE_DIR="$ROOT/.claude/session-state"` pair shown in `## Solution`, placed before
  `STATE_FILE`/`ARCHIVE_DIR` (both already derive from `STATE_DIR`, no other line changes).
  Acceptance: folded into TASK-C (the new tests exercise this line directly).
- [ ] TASK-C: Add two cases to `tests/test-hooks.sh`'s existing `session-state-save.sh (SPEC-086)`
  section per `## Test plan` below (repo-subdirectory case, worktree case); run the file, fix any
  deviation.

### Phase 3: Polish
- [ ] TASK-D: Run the mechanised negative control (`## Test plan`, bottom) and confirm the
  subdirectory case goes RED under the reverted line, then GREEN again restored.

## After state
- [ ] Running the hook (Stop or SubagentStop) while the session's cwd is a subdirectory of a git
  repo writes `<repo-root>/.claude/session-state/last-state.md`, and creates no
  `<subdirectory>/.claude/session-state/` directory. (Today: it creates the nested copy.)
- [ ] Running the hook inside a git worktree still writes to that WORKTREE's own
  `.claude/session-state/`, not the main checkout's. (Unchanged from today.)
- [ ] Running the hook outside any git work tree still writes to `$PWD/.claude/session-state/`
  and exits 0 (fail-open, unchanged from today).
- [ ] Every existing case in `tests/test-hooks.sh`'s `session-state-save.sh (SPEC-086)` section
  still passes unchanged.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria.
- [ ] The two new `tests/test-hooks.sh` cases (subdirectory, worktree) pass.
- [ ] No regression in the existing `session-state-save.sh (SPEC-086)` cases (scan-prune,
  no-git guard, debounce x3).
- [ ] The negative control (revert `STATE_DIR` to the relative form) makes the subdirectory case
  go RED.

## Verification
`bash tests/test-hooks.sh`

## Test plan

Both new cases live in `tests/test-hooks.sh`'s existing `session-state-save.sh (SPEC-086)`
section (around its current lines 843-884), reusing that section's fixture style: a throwaway
git repo under `mktemp -d "${TMPDIR:-/tmp}/dk-....XXXXXX"`, `run_hook`-equivalent piping
(`echo '{"stop_hook_active":false}' | bash "$KIT_DIR/hooks/session-state-save.sh"`), cleaned up
with `rm -rf` at the end of the block.

1. **Repo subdirectory (the reported bug).** A throwaway repo `SUBDIR_REPO` (`git init -q`, one
   commit so `git rev-parse HEAD` succeeds), with a nested directory
   `SUBDIR_REPO/.claude/handoffs/` (the exact reported shape). Run the hook with
   `cd "$SUBDIR_REPO/.claude/handoffs"`. Assert:
   - `SUBDIR_REPO/.claude/session-state/last-state.md` exists (state landed at the toplevel).
   - `SUBDIR_REPO/.claude/handoffs/.claude/session-state/` does NOT exist (no nested copy).
2. **Worktree keeps its own state (no regression).** From `SUBDIR_REPO`, `git worktree add` a
   second worktree `WT_DIR` on a new branch, with its own nested subdirectory (e.g.
   `WT_DIR/sub/`). Run the hook with `cd "$WT_DIR/sub"`. Assert:
   - `WT_DIR/.claude/session-state/last-state.md` exists (the worktree's OWN toplevel, per
     `git rev-parse --show-toplevel` inside a worktree).
   - `SUBDIR_REPO/.claude/session-state/last-state.md` is unaffected by this second run (no
     cross-contamination between the main checkout and the worktree).
3. **Outside a git repo (existing case, unchanged).** Already covered by the current
   `NOGIT2` case in the same section; add no new assertion, just confirm it still passes (the
   `ROOT="... || $PWD"` fallback keeps this path identical: `$PWD/.claude/session-state`, exit 0).

**Negative control (mechanised):**
```sh
bash lib/gate/negctl.sh "$PWD" 'bash tests/test-hooks.sh' 'git checkout origin/master -- hooks/session-state-save.sh'
```
The mutate command reverts only `hooks/session-state-save.sh` to its pre-fix `STATE_DIR="..."`
form at `origin/master` (no toplevel resolution). `negctl.sh` requires the full suite to go RED
under that reversion (case 1's "no nested dir" assertion fails, since the reverted hook DOES
create `.claude/handoffs/.claude/session-state/`), then restores the worktree's own fixed file
and confirms the suite is GREEN again.

## Edge Cases
1. `git rev-parse --show-toplevel` succeeds but prints a path with a trailing symlink component:
   unaffected, the hook only ever appends `/.claude/session-state` to whatever string `git`
   returns; it never resolves or canonicalizes that path further, matching the fail-open,
   don't-overthink-paths style already used elsewhere in this hook.
2. A bare repository or a repo with no commits yet (`git rev-parse HEAD` would fail further
   down): `--show-toplevel` still succeeds (it needs a work tree, not a commit), so `ROOT`
   resolves normally; the existing `LAST_COMMITS="no commits"` fallback is untouched.
3. Two Stop hooks fire back-to-back from two different subdirectories of the SAME repo (main
   agent in one subdir, a subagent in another): both resolve to the identical `ROOT`, so they
   read/write the SAME `last-state.md` and the SAME `.last-fingerprint`, exactly as if both ran
   at the repo root today. No new race is introduced, the file was already shared repo-wide in
   the pre-bug design; this fix restores that sharing.

## Out of Scope
- `hooks/pre-compact-backup.sh`'s identical `BACKUP_DIR=".claude/backups"` relative path (flagged
  in `## Solution`, not fixed here).
- `hooks/anti-rationalization.sh`'s `.claude/debug` existence check (flagged, not fixed here).
- Switching the hook to read `.cwd` from its JSON input (considered and rejected, see
  `## Solution`).
- Any change to the debounce fingerprint, the archive rotation count, or the recent-files scan;
  none of them build a path from `$PWD`, only `STATE_DIR` did.

## Touches
- hooks/session-state-save.sh
- tests/test-hooks.sh

## Decision Log
- DEC-A: Resolve the root via `git rev-parse --show-toplevel` (falls back to `$PWD` outside a
  repo), not via the hook's JSON `.cwd`. Rationale in `## Solution`: no subprocess-`cd`
  indirection exists in this hook, so `.cwd` and `$PWD` are the same value here, and reading
  `.cwd` would add a dependency for no behavior change.
- DEC-B: `pre-compact-backup.sh` and `anti-rationalization.sh`'s matching relative-path sites are
  named but left unfixed, one commit, one hook, no silent scope creep past the reported bug.

## Open questions
(none)
