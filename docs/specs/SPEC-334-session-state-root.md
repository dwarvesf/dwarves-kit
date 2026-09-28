# Spec: session-state-save.sh and pre-compact-backup.sh cd to the repo root, instead of trusting $PWD
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

`STATE_DIR` is not the only cwd-relative read in the hook. Two more sites depend on the same
assumption that `$PWD` is the repo root:

- Line 74: `for F in $(ls docs/specs/SPEC-*.md 2>/dev/null | sort -r || true); do`, the active
  spec lookup. From a subdirectory this glob matches nothing, so `SPEC_FILE` stays empty and the
  written state carries `Spec: none` even when a real spec is active at the root.
- Line 92: `find . \( -type d ... -prune \) -o \( -type f ... -newer "$MARKER" -print \)`, the
  recently-modified-source scan. From a subdirectory this only walks that subtree, so the
  written `## Files modified this session` list is wrong (too narrow, or empty) instead of
  repo-wide.

Fixing only `STATE_DIR` (the reported symptom) still leaves both of these silently wrong: a run
from a subdirectory would write the STATE FILE to the correct root path, but fill it with
`Spec: none` and a subdir-only file list, exactly the fields crash recovery and `start` read.

The git calls in the hook (`git branch --show-current`, `git status --porcelain`, `git diff
HEAD`, `git log --oneline -5`, `git rev-parse HEAD`, `git rev-parse --is-inside-work-tree`) are
NOT affected either way; git climbs to find `.git` from any subdirectory on its own. Only the
three plain-shell reads/writes above (`STATE_DIR`, the `ls docs/specs/`, the `find .`) are
cwd-relative. That is what masks the bug: branch/commit/diff content in the written state is
always correct, only the file's own location and its Spec/Files sections go wrong.

`hooks/pre-compact-backup.sh` (a PreCompact hook) has the identical shape: `BACKUP_DIR=".claude/
backups"` is cwd-relative, and it independently re-implements the same active-spec `ls docs/
specs/SPEC-*.md` glob and a `find . -name "*.ts" -o ...` recent-files scan, both cwd-relative for
the same reason. Same bug, same fix, brought into this spec (see `## Solution`).

## Solution

Resolve the repo root once, near the top of each hook, and `cd` into it, so every subsequent
relative read or write (`STATE_DIR` / `BACKUP_DIR`, the `docs/specs/SPEC-*.md` glob, the `find .`
scan) resolves against the root instead of `$PWD`. One line covers all three sites per hook,
no other line changes:

```sh
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
cd "$ROOT" 2>/dev/null || true
```

`STATE_DIR`/`BACKUP_DIR` stay relative strings (`".claude/session-state"` / `".claude/backups"`);
only the process's working directory changes, before they are ever read.

`git rev-parse --show-toplevel` returns the WORKTREE's own root when run inside a git worktree
(not the main checkout's root), so a worktree session still keeps its own state directory,
unchanged from today's behavior. Outside a git work tree the command fails (non-zero); the `||`
falls back to `$PWD`, and the following `cd "$PWD"` is a no-op, so the fail-open contract is
unchanged there: the hook still writes somewhere (relative to wherever it was invoked) and still
exits 0.

### Why not use the hook's JSON input `.cwd` instead of `$PWD`

Some PreToolUse hooks in this repo (`board-row-gate.sh`, `context-budget.sh`) read `.cwd` from
the hook's JSON input because THEIR job is to reconstruct where a shell command would have run
after the command text itself does a `cd`/`pushd`/`-C`, the process's own `$PWD` at
hook-execution time is not the value they need. `session-state-save.sh` and
`pre-compact-backup.sh` have no such indirection: they are Stop/SubagentStop/PreCompact hooks,
not wrapping a shell command, and each runs in the session's actual working directory. Claude
Code's hook input carries the SAME cwd these hooks already execute in, so `.cwd` and `$PWD` read
the same value here. Reading `.cwd` would add a `jq` parse and an `INPUT` dependency for no
behavior change. Decision: keep using `$PWD` (via `git rev-parse --show-toplevel`), do not switch
to `.cwd`.

### Other hooks with the same shape (grepped)

`grep -n '"\.claude/` across `hooks/*.sh` `hooks/*.py`, excluding `show-toplevel` hits, finds
three relative-`.claude/`-path sites:

| Hook | Line | In scope? | Why |
|---|---|---|---|
| `hooks/session-state-save.sh` | `STATE_DIR=".claude/session-state"` | Yes | This spec's own reported bug. |
| `hooks/pre-compact-backup.sh` | `BACKUP_DIR=".claude/backups"` | **Yes** | Identical shape (cwd-relative directory, plus its own cwd-relative spec-glob and recent-files scan), the same fix pattern, low risk to add one more hook file and one more test case to this branch. |
| `hooks/anti-rationalization.sh` | `if [ -d ".claude/debug" ]; then` | **No** | Different shape: a read-only existence CHECK gating a nested code path, not a directory this hook creates or writes into. Its own root-resolution question (should the debug-ledger check also anchor at the repo root) is a separate, narrower decision belonging to whoever owns the debug-ledger convention, not to this fix. |

`hooks/anti-rationalization.sh` is the only hook flagged and left untouched by this branch.

## Picture

```
 session cwd (maybe a subdir, e.g. .claude/handoffs/)
        |
        v
 git rev-parse --show-toplevel -----fails (no work tree)----> ROOT = $PWD  (fail-open)
        |
        | succeeds
        v
 ROOT = <repo or worktree top>
        |
        v
 cd "$ROOT" 2>/dev/null || true
        |
        v
 +------------------------+------------------------+------------------------+
 |                        |                        |                        |
 STATE_DIR / BACKUP_DIR   ls docs/specs/            find . (recent-files     (git branch/status/
 (relative, now writes    SPEC-*.md (relative,      scan, relative, now      diff/log: already
 at ROOT)                 now reads ROOT's specs)   bounded to ROOT's tree)  root-correct, unchanged)
```

Same shape applies to `hooks/pre-compact-backup.sh`, `BACKUP_DIR` in place of `STATE_DIR`.

## Design

obvious: one root resolution plus a `cd` at each hook's top; the `.cwd` alternative is
equivalent here (see DEC-A), so it buys nothing over `$PWD`. No new component, no schema change,
no external integration.

## Task Breakdown

### Phase 1: Foundation
- [x] TASK-A: Write this spec.

### Phase 2: Core
- [ ] TASK-B: In `hooks/session-state-save.sh`, insert the `ROOT=...` / `cd "$ROOT" ...` pair
  from `## Solution` before the `STATE_DIR="..."` line (after the debug-logging block, before
  any other read). Leave `STATE_DIR`, `STATE_FILE`, `ARCHIVE_DIR` as relative strings, unchanged.
  No other line changes. Acceptance: folded into TASK-D (the new tests exercise this line
  directly).
- [ ] TASK-C: Apply the identical `ROOT=...` / `cd "$ROOT" ...` pair to
  `hooks/pre-compact-backup.sh`, inserted before its `BACKUP_DIR="..."` line. Leave `BACKUP_DIR`
  relative, unchanged. Acceptance: folded into TASK-D.
- [ ] TASK-D: Add the cases in `## Test plan` below to `tests/test-hooks.sh` (three
  `session-state-save.sh` cases, one `pre-compact-backup.sh` case); run the file, fix any
  deviation.

### Phase 3: Polish
- [ ] TASK-E: Commit TASK-B through TASK-D, then run the mechanised negative controls
  (`## Test plan`, bottom) and confirm each subject hook's subdirectory case goes RED under its
  pinned pre-fix revision, then GREEN again restored.

## After state
- [ ] Running `session-state-save.sh` (Stop or SubagentStop) while the session's cwd is a
  subdirectory of a git repo writes `<repo-root>/.claude/session-state/last-state.md`, with the
  correct active-spec `Status:` line and a repo-wide (not subdir-only) modified-files list, and
  creates no `<subdirectory>/.claude/session-state/` directory. (Today: nested dir, wrong Spec
  line, wrong file list.)
- [ ] Running `pre-compact-backup.sh` (PreCompact) from a subdirectory writes
  `<repo-root>/.claude/backups/...`, creating no nested `<subdirectory>/.claude/backups/`.
  (Today: nested dir.)
- [ ] Running either hook inside a git worktree still writes to that WORKTREE's own `.claude/...`
  directory, not the main checkout's. (Unchanged from today.)
- [ ] Running either hook outside any git work tree still writes relative to `$PWD` and exits 0
  (fail-open, unchanged from today).
- [ ] Every existing case in `tests/test-hooks.sh`'s `session-state-save.sh (SPEC-086)` section
  still passes unchanged.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria.
- [ ] The four new `tests/test-hooks.sh` cases (session-state subdirectory-with-content,
  session-state worktree, session-state outside-repo confirmation, pre-compact-backup
  subdirectory) pass.
- [ ] No regression in the existing `session-state-save.sh (SPEC-086)` cases (scan-prune,
  no-git guard, debounce x3).
- [ ] Both negative controls (session-state-save.sh, pre-compact-backup.sh) go RED under their
  pinned pre-fix revision and GREEN again restored.

## Verification
`bash tests/test-hooks.sh`

## Test plan

All new cases live in `tests/test-hooks.sh`. The three `session-state-save.sh` cases extend its
existing `session-state-save.sh (SPEC-086)` section (around its current lines 843-884), reusing
that section's fixture style: a throwaway git repo under
`mktemp -d "${TMPDIR:-/tmp}/dk-....XXXXXX"`, piping
`echo '{"stop_hook_active":false}' | bash "$KIT_DIR/hooks/session-state-save.sh"`, cleaned up
with `rm -rf` at the end of the block. The `pre-compact-backup.sh` case is a new small section
of its own, same fixture style, piping a PreCompact-shaped input
(`echo '{"session_id":"t"}' | bash "$KIT_DIR/hooks/pre-compact-backup.sh"`).

1. **Repo subdirectory, with content (the reported bug).** A throwaway repo `SUBDIR_REPO`
   (`git init -q`, one commit so `git rev-parse HEAD` succeeds), a fixture spec
   `SUBDIR_REPO/docs/specs/SPEC-001-x.md` containing a `Status: DRAFT` line, and a nested
   directory `SUBDIR_REPO/.claude/handoffs/` (the exact reported shape). Run the hook with
   `cd "$SUBDIR_REPO/.claude/handoffs"`. Assert:
   - `SUBDIR_REPO/.claude/session-state/last-state.md` exists (state landed at the toplevel).
   - `SUBDIR_REPO/.claude/handoffs/.claude/session-state/` does NOT exist (no nested copy).
   - `last-state.md` contains `Spec: DRAFT` (the active-spec glob read the root's
     `docs/specs/`, not the subdirectory's).
2. **Worktree keeps its own state (no regression).** From `SUBDIR_REPO`, `git worktree add` a
   second worktree `WT_DIR` on a new branch, with its own nested subdirectory (e.g.
   `WT_DIR/sub/`). Run the hook with `cd "$WT_DIR/sub"`. Assert:
   - `WT_DIR/.claude/session-state/last-state.md` exists (the worktree's OWN toplevel, per
     `git rev-parse --show-toplevel` inside a worktree).
   - `SUBDIR_REPO/.claude/session-state/last-state.md` is unaffected by this second run (no
     cross-contamination between the main checkout and the worktree).
3. **Outside a git repo (existing case, unchanged).** Already covered by the current `NOGIT2`
   case in the same section; add no new assertion, just confirm it still passes (the
   `ROOT="... || $PWD"` fallback plus the no-op `cd "$PWD"` keep this path identical: writes
   relative to `$PWD`, exit 0).
4. **`pre-compact-backup.sh`, repo subdirectory.** A throwaway repo `PCB_REPO` (`git init -q`,
   one commit) with a nested directory `PCB_REPO/.claude/handoffs/`. Run the hook with
   `cd "$PCB_REPO/.claude/handoffs"`. Assert:
   - `PCB_REPO/.claude/backups/` contains a `backup-*.md` file (landed at the toplevel).
   - `PCB_REPO/.claude/handoffs/.claude/backups/` does NOT exist (no nested copy).

**Negative controls (mechanised, run AFTER TASK-B through TASK-D are committed):**
```sh
bash lib/gate/negctl.sh "$PWD" 'bash tests/test-hooks.sh' 'git show afb52d01:hooks/session-state-save.sh > hooks/session-state-save.sh'
bash lib/gate/negctl.sh "$PWD" 'bash tests/test-hooks.sh' 'git show afb52d01:hooks/pre-compact-backup.sh > hooks/pre-compact-backup.sh'
```
`afb52d01` is the pre-fix revision (this branch's parent tip): both files there still have the
cwd-relative `STATE_DIR`/`BACKUP_DIR` line and no `cd "$ROOT"`. Each mutate command pins that
one file back to its pre-fix content; `negctl.sh` refuses to run at all over a dirty tracked
tree, which is why both controls run only once the fix is committed. It requires the full suite
to go RED under the reversion (case 1's "no nested dir" and `Spec: DRAFT` assertions fail for
the first control; case 4's "no nested dir" assertion fails for the second), then restores the
worktree's own fixed file and confirms the suite is GREEN again.

## Edge Cases
1. `git rev-parse --show-toplevel` succeeds but prints a path with a trailing symlink component:
   unaffected, `cd` follows it exactly as any other `cd` target; the hook never resolves or
   canonicalizes the path further, matching the fail-open, don't-overthink-paths style already
   used elsewhere in these hooks.
2. A bare repository, or a cwd already inside the `.git` directory itself: `git rev-parse
   --show-toplevel` FAILS in both cases (there is no work tree to report), so `ROOT` falls back
   to `$PWD` and the following `cd "$PWD"` is a no-op; the hook still writes relative to
   wherever it was invoked, unchanged fail-open behavior, not a special case.
3. Two Stop hooks fire back-to-back from two different subdirectories of the SAME repo (main
   agent in one subdir, a subagent in another): both `cd` to the identical `ROOT`, so both read
   and write the SAME `last-state.md`, the SAME `.last-fingerprint`, and the SAME
   `docs/specs/SPEC-*.md` glob, exactly as if both ran at the repo root today. No new race is
   introduced; the file was already shared repo-wide in the pre-bug design, this fix restores
   that sharing (and, as a side effect, now also shares the correct Spec/Files sections instead
   of each subdir computing its own wrong version).

## Out of Scope
- `hooks/anti-rationalization.sh`'s `.claude/debug` existence check (flagged in `## Solution`,
  not fixed here, different shape).
- Switching either hook to read `.cwd` from its JSON input (considered and rejected, see
  `## Solution`).
- Any change to the debounce fingerprint computation, the archive rotation count, or the
  backup-numbering logic; this fix only changes WHERE their relative paths resolve, not how they
  compute their content.

## Touches
- hooks/session-state-save.sh
- hooks/pre-compact-backup.sh
- tests/test-hooks.sh

## Decision Log
- DEC-A: Resolve the root via `git rev-parse --show-toplevel` (falls back to `$PWD` outside a
  repo), not via the hook's JSON `.cwd`. Rationale in `## Solution`: no subprocess-`cd`
  indirection exists in either hook, so `.cwd` and `$PWD` are the same value here, and reading
  `.cwd` would add a dependency for no behavior change.
- DEC-B: Fix by `cd`-ing into the resolved root and keeping `STATE_DIR`/`BACKUP_DIR` relative,
  rather than building an absolute `$ROOT/.claude/...` path. One line then covers all three
  cwd-relative reads per hook (the state/backup dir, the `docs/specs/SPEC-*.md` glob, the
  `find .` recent-files scan), instead of fixing the reported directory alone and leaving the
  other two silently wrong.
- DEC-C: `pre-compact-backup.sh`'s identical bug is fixed in this same branch (was originally
  scoped out, revised after validation): same root cause, same one-line pattern, one more hook
  file and one more test case is a small, contained widen, not a silent one.
- DEC-D: `hooks/anti-rationalization.sh`'s `.claude/debug` check stays out of scope: a read-only
  existence check gating a different code path, not a directory either fixed hook creates or
  writes into; its own fix (if any) belongs to whoever owns the debug-ledger convention.

## Open questions
(none)
