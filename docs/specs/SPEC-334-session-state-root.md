# Spec: one repo-root anchor for every dwarves-kit hook
Generated: 2026-09-28
Status: DRAFT
Lane: full

## Problem

`hooks/session-state-save.sh` (Stop and SubagentStop) sets `STATE_DIR=".claude/session-state"`,
a path relative to the hook's `$PWD`. From a repo subdirectory (observed: a session sitting in
`ops-toolkit/.claude/handoffs/`) it writes a NESTED copy,
`ops-toolkit/.claude/handoffs/.claude/session-state/`, instead of the repo root every reader of
that file expects.

`STATE_DIR` is not the only cwd-relative read in that one hook. Two more sites in the same file
depend on the same wrong assumption:

- `for F in $(ls docs/specs/SPEC-*.md 2>/dev/null | sort -r || true); do` (the active-spec
  lookup): from a subdirectory this glob matches nothing, so the written state carries
  `Spec: none` even when a real spec is active at the root.
- `find . \( -type d ... -prune \) -o \( -type f ... -newer "$MARKER" -print \)` (the
  recently-modified-source scan): from a subdirectory this only walks that subtree, so the
  written file list is too narrow instead of repo-wide.

Pulling that thread past this one hook, the same shape recurs across the wired hook set:

- `hooks/pre-compact-backup.sh` (PreCompact): `BACKUP_DIR=".claude/backups"`, an identical
  `docs/specs/SPEC-*.md` glob, and its own `find .` recent-files scan.
- `hooks/post-compact-reinject.sh` (PostToolUse, matcher `compact`): reads `CLAUDE.md`,
  the same `docs/specs/SPEC-*.md` glob, AND `find .claude/backups -name "*.md" | sort | tail -1`,
  the READ half of the pair `pre-compact-backup.sh` WRITES. Both are cwd-relative
  independently; if only one of the pair anchored, the reader would look in the wrong place for
  what the writer just wrote.
- `hooks/anti-rationalization.sh` (Stop): `[ -d ".claude/debug" ]` and
  `find .claude/debug -maxdepth 1 ...`, gating the guess-fix guard.
- `hooks/spec-drift-guard.sh` (PreToolUse, matcher `Write`): the same `docs/specs/SPEC-*.md`
  glob, gating whether a new file is checked against the active spec at all.
- `hooks/context-readiness.sh` (SessionStart): `[ -f "CLAUDE.md" ]`, the same
  `docs/specs/SPEC-*.md` glob, and a `find .` for a source-file count.
- `hooks/slop-cleaner.sh` (Stop): a `find .` recent-files scan (already bounded to inside a git
  work tree, already prunes heavy directories during traversal per SPEC-086, but still starts
  from `$PWD`, not the root).

This is a repo-wide pattern, at least seven of the roughly two dozen hooks wired in
`hooks/hooks.json` assume `$PWD` is the repo root and silently degrade (wrong directory, empty
glob, narrow scan) when a session's cwd is a subdirectory. The git calls scattered through these
same hooks (`git branch --show-current`, `git status --porcelain`, `git log`, `git diff HEAD`,
`git rev-parse --is-inside-work-tree`) are unaffected either way, git climbs to `.git` from any
subdirectory on its own; only the plain-shell relative reads and writes are wrong. Fixing
`session-state-save.sh` alone, or even that hook plus `pre-compact-backup.sh`, would leave the
rest of the class silently broken and would not stop a NEW hook from reintroducing the same bug.
Operator decision: fix the class once, with one shared anchor every hook goes through, enforced
so a future hook cannot bypass it silently.

## Solution

### The anchor

A new file, `hooks/anchor-root.sh`:

```sh
#!/bin/bash
# anchor-root.sh -- cd to the repo (or worktree) root, then run the given hook command.
# Every hooks.json entry routes through this (see the one named exclusion below), so no
# hook ever reads or writes relative to the wrong directory because a session's cwd
# happened to be a subdirectory.
#
# Usage: anchor-root.sh <hook-path> [args...]
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
cd "$ROOT" 2>/dev/null || true
exec "$@"
```

`git rev-parse --show-toplevel` returns the WORKTREE's own root inside a worktree (not the main
checkout's), so a worktree session still keeps its own state. Outside a git work tree the
command fails; the `||` falls back to `$PWD`, and the following `cd "$PWD"` is a no-op, so a
hook running outside any repo behaves exactly as it does today. `exec "$@"` replaces the wrapper
process with the target hook, so stdin (the hook's JSON payload), stdout, stderr, and the exit
code all pass through untouched, the same reasoning `citation-guard.sh` already gives for using
`exec` instead of a wrapped call.

Every `hooks/hooks.json` `command` entry is rewritten to
`${CLAUDE_PLUGIN_ROOT}/hooks/anchor-root.sh <original command>`, verbatim, with ONE named
exclusion (`hooks/secrets-guard.sh`'s entry, left exactly as it is today, see below). No hook
FILE itself changes; the fix lives entirely in the new wrapper plus the `hooks.json` rewrite. A
`.sh` hook that is itself a thin shim into a `.py` counterpart (`harvest.sh` → `harvest.py`,
`citation-guard.sh` → `citation-guard.py`, `backlog-stage.sh`/`context-hints.sh`/
`intake-sweep.sh`/`money-gate.sh` likewise) inherits the anchored cwd from its parent process
without any change to the `.py` file either, `hooks.json` only ever names the `.sh` entry point,
so anchoring at that one dispatch layer covers `.sh` and `.py` hooks alike with nothing
language-specific.

### Rejected alternatives

- **A two-line anchor pasted into every hook file** (or the same idea factored as a helper each
  hook `source`s at its own top). Rejected: touches roughly fifteen files individually, and
  nothing stops a NEW hook file from omitting the paste or the `source` line, the exact
  regression this fix must close off. A per-file convention cannot be mechanically checked the
  way one dispatch table can.
- **`$CLAUDE_PROJECT_DIR`.** Rejected: it is a fixed per-session environment variable pointing at
  the ORIGINAL project directory, not derived from the hook's actual invocation cwd. Inside a
  worktree session it would resolve to the MAIN checkout, not the worktree's own root, breaking
  "a worktree session keeps its own state" (`git rev-parse --show-toplevel` is worktree-aware,
  confirmed earlier in this spec's history; a static env var cannot be).

### Precedent already in this codebase

Seven hooks already resolve their own root the same way, independently, before this spec:
`ship-gate.sh` and `commit-format.sh` (`git rev-parse --show-toplevel`, falling back to their
own `$PWD`/`pwd`), `codebase-index.sh` (identical pattern), and `harvest.py`, `backlog-stage.py`,
`intake-sweep.py` (each has its own `_repo_root()` doing the same git call, falling back to
`os.getcwd()`). The anchor consolidates a pattern this codebase already reinvented seven times
into one place, rather than introducing something novel.

### Full enumeration

Every hook wired in `hooks/hooks.json`, checked two ways: the exact grep the validator named,
`grep -n '\.claude/\|docs/specs\|CLAUDE\.md\|find \.' hooks/*.sh hooks/*.py`, plus a broader sweep
for `$PWD`/`` `pwd` ``/`os.getcwd()` to catch reads the first pattern's literal strings miss.

**Table 1: fixed by the anchor (today's bug class)**

| Hook | Event | cwd-relative site | Effect of anchoring |
|---|---|---|---|
| `session-state-save.sh` | Stop, SubagentStop | `STATE_DIR`, the spec glob, `find .` | The reported bug; state lands at the root with the right Spec/Files sections |
| `pre-compact-backup.sh` | PreCompact | `BACKUP_DIR`, the spec glob, `find .` (unpruned) | Backup lands at the root; see the PreCompact-timeout edge case below |
| `post-compact-reinject.sh` | PostToolUse (`compact`) | `CLAUDE.md`, the spec glob, `.claude/backups` reader | Now reads the SAME root `pre-compact-backup.sh` just wrote (the writer/reader pair) |
| `anti-rationalization.sh` | Stop | `.claude/debug` check + `find .claude/debug` | The guess-fix guard now fires correctly from any subdirectory; a `$(pwd)` log line becomes cosmetic-only |
| `spec-drift-guard.sh` | PreToolUse (`Write`) | the spec glob | The drift check stops silently no-op'ing from a subdirectory (today: empty glob, whole check exits with nothing checked) |
| `context-readiness.sh` | SessionStart | `CLAUDE.md`, the spec glob, `find .` | Readiness warnings stop misfiring ("no CLAUDE.md", "no spec") from a subdirectory where both exist at the root |
| `slop-cleaner.sh` | Stop | `find .` (already pruned, already work-tree-guarded) | Scans the whole repo instead of the cwd's subtree, same class of fix as case 1; no new test case added (structurally covered by the same mechanism) |

**Table 2: already self-anchored or immune, the wrapper is a no-op**

| Hook | Why unaffected |
|---|---|
| `ship-gate.sh` | Already resolves its own `ROOT` via `git -C "$CDDIR" rev-parse --show-toplevel` or the same call from its own `$PWD` |
| `commit-format.sh` | Already does `git rev-parse --show-toplevel 2>/dev/null \|\| pwd` for its own policy-root lookup |
| `codebase-index.sh` | Already does `REPO="$(git rev-parse --show-toplevel 2>/dev/null \|\| pwd)"` |
| `safety-gate.sh` | `$(pwd)` appears only in its audit `log_block` line, never in a gating decision |
| `board-row-gate.sh` | `.cwd` from the JSON payload wins whenever present (the normal case); anchoring only touches the rare fallback where `.cwd` is absent |
| `batch-debt-warn.sh` | `ledger_root` resolves via a `$HOME`-scoped ledger path, not cwd-derived |
| `tool-policy-guard.sh` | Policy path is `$HOME`/`KIT_TOOL_POLICY`; tool name comes from the payload; no cwd read at all |
| `money-gate.py` | Reads `payload.get("cwd")` only, never `os.getcwd()` |
| `context-budget.sh` | Reads `.cwd` from the payload with NO `$PWD` fallback at all; an absent `.cwd` just skips two settings-file checks |
| `citation-guard.py` | `payload.get("cwd")` wins before its `os.getcwd()` fallback; anchoring only touches that last resort, and only makes it MORE correct |
| `harvest.py`, `backlog-stage.py`, `intake-sweep.py` | Each already has its own `_repo_root()` doing `git rev-parse --show-toplevel`, falling back to `os.getcwd()` only on failure |
| `prose-rag.sh` | Its `pwd` resolves the SCRIPT's own directory (`cd "$(dirname ...)" && pwd`), not the session cwd, an unrelated use |
| `context-hints.py`, `notification.sh`, `permission-auto-approve.sh`, `output-offload.sh` | No cwd/pwd/`getcwd()` reference found in any of the four |

**Relies on cwd on purpose:**

- **`secrets-guard.sh`** (PreToolUse, matcher `Read|Edit|Bash`): `normpath()` resolves a RELATIVE
  path OPERAND from `tool_input` against `$PWD` (`case "$p" in /*) ;; *) p="$PWD/$p" ;; esac`) to
  canonicalize it for the secret-file denylist match. This must use the REAL invocation
  directory, the same directory the tool call itself would resolve the relative path against,
  not the repo root. Anchoring this hook would canonicalize a relative path against the wrong
  base directory, a security-relevant correctness regression: a relative path could dodge, or
  wrongly trip, the denylist. **Excluded**: its `hooks.json` entry is the one named exception,
  left exactly as it runs today.
- **`auto-format.sh`** (PostToolUse, matcher `Write|Edit`): `find_prettier()` checks
  `./node_modules/.bin/prettier` relative to `$PWD`, to find a monorepo package's own local
  formatter. Anchoring could miss a non-hoisted package-local install and fall back to a global
  `prettier` or skip silently. Lower severity than `secrets-guard.sh`: the hook already "exits 0
  always" and is advisory-only, it never blocks or gates anything. Accepted as a minor,
  out-of-scope cosmetic tradeoff; **not excluded** from the anchor.

### The self-enforcing lint

`tests/test-hook-anchor.sh` (new, a sibling of `tests/test-hooks.sh`, picked up automatically by
`tests/run-all.sh`'s `tests/test-*.sh` glob):

1. Parses `hooks/hooks.json` with `jq` and lists every `command` string across every hook event.
2. For each one, asserts the string starts with `${CLAUDE_PLUGIN_ROOT}/hooks/anchor-root.sh `,
   EXCEPT the single named exemption (`secrets-guard.sh`, matched by its basename, with the
   reason from `## Solution` inlined as a comment next to the exemption list, not a bare
   allowlist with no explanation).
3. A small embedded fixture (a hand-written JSON snippet with one entry missing the wrapper) is
   run through the SAME check function first, asserting the checker itself correctly flags a
   bypass. This proves the check's logic is exercised, not merely vacuously true because the
   real file already complies.
4. Then the same check runs against the real `hooks/hooks.json`.

A future hook entry added without the wrapper (and not the named exemption) fails step 4
immediately.

### Explicitly out of scope

- **Switching any hook to read `.cwd` from its JSON payload instead of the anchor.** We found no
  in-repo mechanism (no `cd`, no subshell) between Claude Code's dispatch and a hook's own
  process that would make `$PWD` differ from the payload's `.cwd` for these events. We do not
  claim the two are certified equal by Claude Code itself, we have no citable source for that;
  we simply have nothing in this repo that would make them differ, and reading `.cwd` would
  still need the identical `git rev-parse --show-toplevel` step afterward (a payload field is
  not itself a repo root), so it buys nothing over anchoring from `$PWD` directly.
- **`pre-compact-backup.sh`'s NEXT-count glob bug.** Its `COUNT=$(find "$BACKUP_DIR" -name
  "backup-*.md" ...)` never matches an existing file: every backup is actually named
  `<N>-backup-<timestamp>.md`, not `backup-*.md`. `COUNT` is always 0, so `NEXT` is always 1;
  the numbering never increments. Pre-existing, independent of cwd resolution, not fixed here
  (our own test glob below uses the correct `*-backup-*.md` pattern to avoid the same mistake).
- **`post-compact-reinject.sh`'s lexical `sort | tail -1`.** `find .claude/backups -name "*.md" |
  sort | tail -1` sorts backup filenames as plain strings. Past nine backups this breaks
  (`"10-backup-..."` sorts before `"2-backup-..."`). Pre-existing, independent of cwd resolution,
  not fixed here.
- **`codex-hooks.json`.** A separate runtime's hook wiring (Codex, not Claude Code); AGENTS.md
  already states enforcement is Claude-Code-only. If the same class of bug exists there, that is
  a follow-up, not this spec.
- **`hooks/intake-sweep.sh`.** Not wired anywhere in `hooks/hooks.json` today (invoked some other
  way); the anchor mechanism only covers hooks `hooks.json` dispatches, so it does not apply.
- **`auto-format.sh`'s prettier-lookup caveat** (named above): accepted, not fixed.

## Picture

```
 session cwd (maybe a subdir, e.g. .claude/handoffs/)
        |
        v
 Claude Code dispatches the hooks.json command:
 <plugin>/hooks/anchor-root.sh <plugin>/hooks/<hook>.sh [args]
        |
        v
 anchor-root.sh:
   git rev-parse --show-toplevel --fails (no work tree)--> ROOT = $PWD  (fail-open)
        |
        | succeeds (repo or worktree top)
        v
   cd "$ROOT" 2>/dev/null || true
        |
        v
   exec "$@"   -->  <hook>.sh runs with cwd = ROOT, exit code/stdio pass through untouched
        |
        v
 <hook>.sh's own relative reads/writes (.claude/..., docs/specs/*, find .)
 now resolve against ROOT, not the session's true subdirectory

 ONE named exception: secrets-guard.sh's hooks.json entry has no anchor-root.sh prefix,
 it keeps running at the tool's real invocation cwd (needed to canonicalize a relative
 path OPERAND the same way the tool call itself would).
```

## Design

obvious: one shared wrapper, referenced from every `hooks.json` entry but one, plus a lint that
fails if a future entry skips it. No hook file's own code changes. The `.cwd`-instead-of-`$PWD`
alternative is equivalent here and buys nothing (see `## Solution`, Out of scope).

## Task Breakdown

### Phase 1: Foundation
- [x] TASK-A: Write this spec.

### Phase 2: Core
- [ ] TASK-B: Add `hooks/anchor-root.sh` per `## Solution`.
- [ ] TASK-C: Rewrite every `command` entry in `hooks/hooks.json` to
  `${CLAUDE_PLUGIN_ROOT}/hooks/anchor-root.sh <original command>`, except `secrets-guard.sh`'s
  entry (left unchanged, with a one-line JSON-adjacent comment impossible in JSON itself, so the
  reason lives in `tests/test-hook-anchor.sh`'s exemption list and in this spec, not in
  `hooks.json`). No other field in any entry changes.
- [ ] TASK-D: Add `tests/test-hook-anchor.sh` per `## Solution`, "The self-enforcing lint".
- [ ] TASK-E: In `tests/test-hooks.sh`, add the five cases in `## Test plan` below, each invoking
  its hook THROUGH the wrapper (`bash "$KIT_DIR/hooks/anchor-root.sh" "$KIT_DIR/hooks/<hook>.sh"
  [args]`), not the bare hook. Existing cases that invoke hooks directly are untouched, they test
  a hook's own internal logic (debounce, prune, scan-bound) and are unaffected by this fix either
  way, since those fixtures already sit at their own repo root.

### Phase 3: Polish
- [ ] TASK-F: Commit TASK-B through TASK-E, then run both negative controls in `## Test plan`
  (bottom) and confirm each goes RED under its mutation, then GREEN again restored.

## After state
- [ ] Every hook in Table 1 (`session-state-save.sh`, `pre-compact-backup.sh`,
  `post-compact-reinject.sh`, `anti-rationalization.sh`, `spec-drift-guard.sh`,
  `context-readiness.sh`, `slop-cleaner.sh`) reads and writes relative to the repo/worktree root
  when dispatched through `hooks.json`, regardless of which subdirectory the session's cwd is
  in. (Today: relative to whatever subdirectory the session happens to sit in.)
- [ ] `secrets-guard.sh` is unchanged: it keeps resolving relative path operands against the
  tool's real invocation cwd.
- [ ] A worktree session's hooks still write to that worktree's OWN `.claude/...` directories,
  not the main checkout's.
- [ ] A hook run outside any git work tree still behaves exactly as it does today (relative to
  `$PWD`, fail-open, exit 0 where that was already the contract).
- [ ] `tests/test-hook-anchor.sh` fails if a future `hooks.json` entry is added without routing
  through `anchor-root.sh`, unless it is added to the same named exemption list with a reason.
- [ ] Every existing case in `tests/test-hooks.sh` still passes unchanged.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria.
- [ ] The five new `tests/test-hooks.sh` cases pass (session-state subdirectory-with-content,
  session-state worktree, session-state outside-repo confirmation, pre-compact-backup
  subdirectory, post-compact-reinject writer/reader pair).
- [ ] `tests/test-hook-anchor.sh` passes: every `hooks.json` entry is wrapped except the one
  named exemption, and its embedded bypass fixture is correctly flagged.
- [ ] No regression in existing `tests/test-hooks.sh` cases.
- [ ] Both negative controls go RED under their mutation and GREEN again restored.

## Verification
`bash tests/test-hooks.sh && bash tests/test-hook-anchor.sh`

## Test plan

All new cases live in `tests/test-hooks.sh`, reusing its existing fixture style: a throwaway git
repo under `mktemp -d "${TMPDIR:-/tmp}/dk-....XXXXXX"`, JSON piped on stdin, cleaned up with
`rm -rf`. Every new case invokes its hook THROUGH the wrapper:
`bash "$KIT_DIR/hooks/anchor-root.sh" "$KIT_DIR/hooks/<hook>.sh" [args]`, not the bare hook.

1. **`session-state-save.sh`, repo subdirectory, with content (the reported bug).** A throwaway
   repo `SUBDIR_REPO` (`git init -q`, one commit), a fixture spec
   `SUBDIR_REPO/docs/specs/SPEC-001-x.md` containing `Status: DRAFT`, a nested directory
   `SUBDIR_REPO/.claude/handoffs/`, and set `DWARVES_KIT_SESSION_MARKER` to a marker file timed
   in the past (matching the existing SPEC-086 block's convention). Add a root-level
   `SUBDIR_REPO/touched.py` newer than the marker. Run the wrapper with
   `cd "$SUBDIR_REPO/.claude/handoffs"`. Assert:
   - `SUBDIR_REPO/.claude/session-state/last-state.md` exists (landed at the toplevel).
   - `SUBDIR_REPO/.claude/handoffs/.claude/session-state/` does NOT exist (no nested copy).
   - `last-state.md` contains `Spec: DRAFT` (the spec glob read the root's `docs/specs/`).
   - `last-state.md` contains `touched.py` under `## Files modified this session` (the `find .`
     scan reached the root, not just the subdirectory).
2. **`session-state-save.sh`, worktree keeps its own state (no regression).** From
   `SUBDIR_REPO`, `git worktree add "$WT_DIR" -b <branch>` where `WT_DIR` is a SIBLING mktemp
   directory (`mktemp -d "${TMPDIR:-/tmp}/dk-wt.XXXXXX"`, outside `SUBDIR_REPO`'s own tree, the
   normal `git worktree add` shape), with its own nested subdirectory `WT_DIR/sub/`. Before
   running, checksum `SUBDIR_REPO/.claude/session-state/last-state.md`
   (`shasum "$SUBDIR_REPO/.claude/session-state/last-state.md"`). Run the wrapper with
   `cd "$WT_DIR/sub"`. Assert:
   - `WT_DIR/.claude/session-state/last-state.md` exists (the worktree's OWN toplevel).
   - The checksum of `SUBDIR_REPO/.claude/session-state/last-state.md` is UNCHANGED (byte-for-
     byte identical to before this run), proving no cross-contamination between the main
     checkout and the worktree.
3. **`session-state-save.sh`, outside a git repo (existing case, unchanged).** Already covered
   by the current `NOGIT2` case; confirm it still passes through the wrapper too (the
   `ROOT="... || $PWD"` fallback plus the no-op `cd "$PWD"` keep this path identical).
4. **`pre-compact-backup.sh`, repo subdirectory.** A throwaway repo `PCB_REPO` (`git init -q`,
   one commit), a fixture spec `PCB_REPO/docs/specs/SPEC-001-x.md`, and a nested directory
   `PCB_REPO/.claude/handoffs/`. Run the wrapper with `cd "$PCB_REPO/.claude/handoffs"`. Assert:
   - `PCB_REPO/.claude/backups/` contains a file matching `*-backup-*.md` (the real naming
     shape, `<N>-backup-<timestamp>.md`, not the hook's own broken `backup-*.md` glob, see
     `## Solution`, Out of scope).
   - `PCB_REPO/.claude/handoffs/.claude/backups/` does NOT exist (no nested copy).
   - The backup file's content contains `Spec: docs/specs/SPEC-001-x.md` (the spec glob also
     read the root).
5. **The writer/reader pair.** From the same `PCB_REPO` and subdirectory as case 4, immediately
   run `post-compact-reinject.sh` through the wrapper (same cwd,
   `cd "$PCB_REPO/.claude/handoffs"`). Assert its JSON `additionalContext` output contains
   `BACKUP: .claude/backups/` (it found the file `pre-compact-backup.sh` just wrote, at the same
   resolved root, not a stale or missing path).

**Negative control 1 (the anchor's own cd).** `hooks/anchor-root.sh` is a new file with no
pre-fix revision to pin to (`afb52d01` predates its existence), so its mutation is a no-op
passthrough rather than a `git show` pin:
```sh
bash lib/gate/negctl.sh "$PWD" 'bash tests/test-hooks.sh' "printf '#!/bin/bash\nexec \"\$@\"\n' > hooks/anchor-root.sh"
```
This overwrites the wrapper with a version that execs straight through, no `cd`, the exact
regression this fix guards against (someone edits the wrapper and drops the `cd` line).
`negctl.sh` requires cases 1, 2, and 4's "no nested dir" assertions to fail under that mutation,
then restores the real `anchor-root.sh` and confirms green again.

**Negative control 2 (the bypass lint).** `hooks/hooks.json` DOES exist at `afb52d01`, in its
pre-fix form where no entry has the wrapper:
```sh
bash lib/gate/negctl.sh "$PWD" 'bash tests/test-hook-anchor.sh' 'git show afb52d01:hooks/hooks.json > hooks/hooks.json'
```
Reverting `hooks.json` to that revision removes the wrapper from every entry; `negctl.sh`
requires `tests/test-hook-anchor.sh` to go RED (every entry now lacks the prefix), then restores
the real `hooks.json` and confirms green again.

## Edge Cases
1. `git rev-parse --show-toplevel` succeeds but prints a path with a trailing symlink component:
   unaffected, `cd` follows it exactly as any other target; nothing resolves or canonicalizes it
   further.
2. A bare repository, or a cwd already inside the `.git` directory itself: `git rev-parse
   --show-toplevel` FAILS in both cases (no work tree to report), so `ROOT` falls back to `$PWD`
   and the following `cd` is a no-op; unchanged fail-open behavior, not a special case.
3. Two Stop hooks fire back-to-back from two different subdirectories of the SAME repo (main
   agent in one, a subagent in another): both anchor to the identical `ROOT`, so both read and
   write the SAME state files and the SAME spec glob, as if both ran at the repo root today. No
   new race, the file was already meant to be shared repo-wide.
4. **`pre-compact-backup.sh`'s `find .` is unpruned** (it filters heavy directories with
   post-hoc `grep -v` rather than pruning them during traversal, unlike `session-state-save.sh`
   and `slop-cleaner.sh`, both already fixed by SPEC-086). Anchoring it to the repo root from a
   subdirectory session makes this scan WALK MORE of the tree than it does today (today it is
   accidentally bounded by whatever subtree the session's cwd happens to sit in). On a large
   repo this risks pushing the hook closer to, or past, its own 15-second PreCompact timeout.
   Not fixed here (the prune-during-traversal rewrite is a separate, scoped change to that one
   hook's own scan, see `## Solution`, Out of scope); named so it is not a silent regression.

## Out of Scope
See `## Solution`, "Explicitly out of scope", for the full list and reasoning:
- Switching any hook to read `.cwd` instead of anchoring from `$PWD`.
- `pre-compact-backup.sh`'s NEXT-count glob bug (`backup-*.md` vs the real `<N>-backup-*.md`).
- `post-compact-reinject.sh`'s lexical `sort | tail -1` (breaks past nine backups).
- `codex-hooks.json` (a separate runtime's wiring).
- `hooks/intake-sweep.sh` (not wired via `hooks.json`).
- `auto-format.sh`'s prettier-lookup caveat (accepted, not fixed).
- `secrets-guard.sh`'s exclusion from the anchor (by design, not an oversight).

## Touches
- hooks/anchor-root.sh (new)
- hooks/hooks.json
- tests/test-hook-anchor.sh (new)
- tests/test-hooks.sh

## Decision Log
- DEC-A: One shared wrapper referenced from `hooks.json`, not a per-hook pasted or sourced
  anchor. Rationale: only a single dispatch table can be mechanically checked for a bypass; a
  per-file convention cannot.
- DEC-B: `secrets-guard.sh` is excluded from the anchor. It resolves a relative path OPERAND
  from `tool_input` against the tool's real invocation cwd, a security-relevant use that the
  repo root would break. `auto-format.sh` has a similar but lower-severity dependency
  (a monorepo's local prettier lookup); kept anchored, flagged as an accepted tradeoff, because
  it is advisory-only and already fails soft.
- DEC-C: No hook file's own code changes. The entire fix is the new wrapper plus the `hooks.json`
  rewrite, so the class stays fixed in one place instead of drifting across per-hook patches
  again.
- DEC-D: Dropped an earlier, unverified claim that the hook JSON payload's `.cwd` field always
  equals the hook's own `$PWD`. No citable source for that equality exists in this repo; the
  decision to anchor from `$PWD` rests instead on there being no in-repo indirection that would
  make them differ for these events, and on `.cwd` needing the identical `git rev-parse
  --show-toplevel` step regardless.
- DEC-E: Softened an earlier claim that `/kit:start` reads `last-state.md`. No code reader of
  that file exists in this repo today (`lib/adopt.sh` only lists it as part of the `session`
  install module's file manifest); the audience for a correctly-placed state file is crash
  recovery and a human skimming the repo, not a verified `start` code path.

## Open questions
(none)
