# Spec: wrap apply --archive-worktrees archives stale unmerged and detached worktrees
Generated: 2026-10-31
Status: DRAFT
Lane: full
Depth: blind-spot (failure: the gitlink tree guard has no isolated negative control, so a change that disables it alone goes unseen while the status guard masks it)
References: `lib/wrap/wrap-apply.sh:354-427` (`_apply_archive_unmerged`; imitate its slug, its pre-read of the archive ref, its post-push `ls-remote` tip check, and its leased `update-ref --no-deref -d` branch delete); `lib/wrap/wrap-apply.sh:185-287` (`_apply_worktrees`; imitate its NUL-delimited worktree loop, its guard order, its `-f -f` removal and its `_wt_cleared` postcondition); `lib/wrap/wrap-apply.sh:87-91` (`_wt_lock_live`), `:121-181` (`_wt_busy`), `:96-101` (`_wt_cleared`), `:10-26` (`_merge_proof`), `:341-343` (`_archive_slug`), all reused as is; `lib/wrap/wrap-apply.sh:486-499` (`_apply_origin_branches`; the `--force-with-lease=<ref>:<expect>` push form); `lib/wrap/wrap-land.sh:226-272` (`_LAND_IGNORED_BUILTIN`, `_land_ignored_allowed`; the matcher this spec extracts) and `:366` (the secret-shaped basename pattern); `lib/wrap/wrap-common.sh:95` (`_mtime`), `:168-185` (`_write_guard`); `tests/test-wrap-apply.sh:715-819` (the `--archive-unmerged` fixture and case shapes).

## Problem

`wrap apply --archive-unmerged` archives only local branches that are not current, default, or held by a worktree. `wrap apply --worktrees` removes only worktrees whose branch is proven merged. It skips a dirty worktree, a detached one, and an unproven one by design.

So two kinds of worktree are never touched by any verb:
- a worktree whose branch carries work origin/<default> lacks;
- a worktree on a detached HEAD with commits origin lacks.

They pile up forever. Their branches pile up with them, because `--archive-unmerged` skips every worktree-held branch.

One session archived three such worktrees by hand. Per worktree it ran five steps: snapshot the uncommitted files in a commit, push the tip to origin `archive/<slug>-<date>`, verify the remote ref, `git worktree remove`, and delete the local branch. The kit's own hooks blocked the hand version twice: a push inside a script, and a push with a command substitution. The hooks are right to block those shapes, so the job belongs inside `wrap`, where the push is one of its declared writes.

Two more gaps showed up while grounding this spec:
- The existing archive push is a plain `git push`. A plain push to an existing ref fast-forwards it (sampled in `## Grounding`). The pre-read with `ls-remote` closes that only when no writer races between the read and the push.
- `git worktree remove` deletes gitignored files without a word, `.env` included (sampled). The new sweep must not lose one.

## Terms

The repo has no `CONTEXT.md` glossary; recent specs (SPEC-412) keep their terms here, and this spec follows that precedent.

- stale worktree: a registered, non-main worktree whose idle age is at least `wrap.archive_worktree_min_age_hours`.
- idle age: now minus the newest of: the newest reflog entry's own time (`git -C <wt> log -g -1 --date=unix --format=%gd HEAD`, the `{<epoch>}` part; skipped when the reflog is empty), the mtimes of the admin `HEAD`, admin `commondir` and admin `locked` (when present), and the mtime of every path `git status` lists as modified, added, renamed, deleted-in-place or untracked (not ignored). The admin `index` and the admin `logs/HEAD` mtimes are NOT read: a plain `git status` rewrites the first, and `git reflog expire` or `gc --auto` rewrites the second (both sampled).
- archive tip: the commit the sweep pushes. For a clean worktree it is the worktree's HEAD. For a dirty one it is the snapshot commit.
- snapshot commit: a commit built from a temporary index, never the worktree's own index. Its tree is the working tree as `git add -A` sees it (gitignored files excluded). Its parent is HEAD, or the staged commit when one exists.
- staged commit: an extra commit, parent HEAD, holding the worktree's real index tree. Made only when that tree differs from both HEAD's tree and the snapshot tree, so a partly staged file keeps both versions.
- regenerable ignored path: a gitignored path the archive sweep may delete with the worktree, because a build or install recreates it, or the main checkout holds an identical copy. Two classes: the fixed list in code (`_ARCHIVE_IGNORED_REGENERABLE`), and an ignored path under `.claude/` whose every file is byte-identical to the same relative path in the main checkout (DEC-S).
- create-only lease: `git push --force-with-lease=refs/heads/<ref>: <sha>:refs/heads/<ref>`. The empty expect means "the ref must not exist". The push is refused when it exists, even when a plain push would fast-forward it.

## Solution

### Approaches considered
1. Widen `--archive-unmerged` to also archive worktree-held branches and detached worktrees. Tradeoff: an existing opt-in flag starts removing worktrees, a bigger write than any current caller asked for. A caller that passes it today gets a new removal class on upgrade.
2. A new opt-in flag `--archive-worktrees` on `apply`, with its own section and its own guards. Tradeoff: one more flag and one more section, about 200 lines of new sweep code beside the two existing sweeps.
3. Make `--worktrees` archive unproven worktrees instead of skipping them. Tradeoff: `/kit:wrap` step 5 passes `--worktrees` on every call by default, so every session wrap would start pushing to origin and removing other sessions' unmerged work.

### Chosen approach + why
Approach 2. The flag is opt-in and no default flow passes it, the same contract `--archive-unmerged` has. Approach 1 changes what an existing flag does to callers who never asked for worktree removal. Approach 3 turns the default landing step into a remote write over every repo the session touched.

### Extensibility & boundaries
- The dimension that grows is the number of worktrees in a repo (a busy repo held 40+). Per candidate the sweep runs one `git status`, one `git cherry`, one `lsof` pass (about 0.3 s, per `_wt_busy`'s own comment) and, under `--apply`, one push and one `ls-remote`. It stays linear and does no tree walk; the idle age reads only the paths `git status` already listed.
- Units, each with one purpose:
  - `_wt_idle_secs <wt>`: prints the idle age in seconds.
  - `_wt_snapshot <wt>`: builds the archive tip from a temporary index. Prints `<tip> <tree> <n_paths>`. Writes objects only.
  - `_wt_ignored_blockers <wt>`: prints every ignored path that is not regenerable.
  - `_ignored_match <path> <entries>`: the matcher extracted from `_land_ignored_allowed`, shared by land and the archive sweep.
  - `_apply_archive_worktrees <repo> <def> <cur> <fetch_ok> <ghs>`: the loop, the guards, the push, the removal.

## Picture

```
 wrap apply [--apply] --archive-worktrees <repo>
        |
        v
 _apply_repo
   |-- _apply_worktrees        (--worktrees: proven-merged, clean -> removed; unchanged)
   |-- _apply_branches         (unchanged)
   |-- _apply_archive_unmerged (--archive-unmerged: unheld branches; unchanged)
   |-- _apply_archive_worktrees   <-- NEW, only with --archive-worktrees
   |      |
   |      |  per registered worktree (git worktree list --porcelain -z)
   |      v
   |    guards: --own / --no-pull / origin / fetch / knob /
   |            busy check available (DEC-R), then per record:
   |            prunable / main / invoking worktree ($PWD, cur) /
   |            protected branch / merge-rebase in progress /
   |            unmerged index or unborn HEAD (DEC-Q)
   |      |
   |      v
   |    candidate?  clean: git cherry origin/<def> <HEAD> has a '+'
   |                dirty: always (the snapshot is unique)
   |                clean + merge-proven: left for --worktrees
   |      |
   |      v
   |    stale?  _wt_idle_secs >= min_age_hours * 3600
   |    lock pid alive?  busy (lsof)?  wt index.lock?  submodule?
   |    embedded git repo (?? dir at any depth holding .git)?
   |    ignored non-regenerable? (fixed list, or .claude/ copy identical
   |                              to the main checkout: DEC-S)
   |    secret-shaped uncommitted path in git status (_ARCHIVE_SECRET_GUARD)?
   |      |   (every git status read: --no-optional-locks; the embedded and
   |      |    secret guards share one --untracked-files=all read)
   |      v  (dry run stops here: WOULD archive worktree ...)
   |    _write_guard <repo>; read HEAD
   |    pre-read: ls-remote --exit-code --heads origin <ref>  (present -> FAILED)
   |      |
   |      v
   |    _wt_snapshot -> archive tip (temp index, objects only)
   |      |
   |      v
   |    tree guards: new gitlink (path + sha) in snapshot tree vs HEAD?
   |                 secret-shaped name in diff-tree HEAD..staged/snapshot?
   |      |          (either -> SKIP, nothing pushed)
   |      v
   |    git push --force-with-lease=refs/heads/<ref>: <tip>:refs/heads/<ref>
   |      |                                  origin
   |      v                                 +------------------------+
   |    ls-remote <ref> == tip ? ---------> | archive/<slug>-<date>  |
   |      |                                 +------------------------+
   |      v
   |    re-read HEAD + snapshot tree, lock, busy  (changed -> kept)
   |      |
   |      v
   |    git worktree remove -f -f <wt>; _wt_cleared
   |      |
   |      v
   |    branch-held: update-ref --no-deref -d refs/heads/<b> <HEAD>
   |                 (HEAD read before the push; the archive tip differs when dirty)
   |                 then config --remove-section branch.<b>
   |
   |-- _apply_origin_branches  (unchanged)
   |-- stray lines / stray commits / pull (unchanged)
```

## Design

### Approaches considered + chosen
See `## Solution`. The design view adds one tradeoff: the snapshot could be a `git stash create` commit. It was rejected because `stash create` has no `-u`, so untracked files, the most common uncommitted work in an agent worktree, would be lost.

### Diagram
The `## Picture` block above is the control-flow diagram. Its order is the contract: no write happens before every guard has passed, and no removal happens before origin holds the archive tip.

Data shape on origin, one ref per archived worktree:

```
 archive/<slug>-<YYYYMMDD>
    |
    snapshot commit  "wrap: snapshot of uncommitted files in <wt>"   (dirty only)
    |
    staged commit    "wrap: staged state of <wt>"                     (only when the index differs)
    |
    HEAD of the worktree (branch tip or detached commit)
    |
    ... history shared with origin/<default>
```

`<slug>` is `_archive_slug <branch>` for a branch-held worktree, and `_archive_slug <worktree basename>` for a detached one (`wt` when that slug is empty).

### ADR link(s)
None. The local half is reversible: every removed worktree is recoverable from its archive ref with `git worktree add <path> archive/<slug>-<date>`. The remote half is NOT: once a path reaches origin, deleting the ref does not undo the disclosure (clones, forks, caches and GitHub's own retention may keep it). That irreversible half is guarded for UNCOMMITTED paths by `_ARCHIVE_SECRET_GUARD` (DEC-I), and the embedded-repo guard (DEC-H) keeps nested repos out; both run before the push. Committed unique commits push unscanned, exactly as `--archive-unmerged` pushes them today (DEC-L, accepted risk). The Decision Log records all of it.

### Boundaries & failure modes
Out of bounds: deleting archive refs, pruning registry entries whose directory is gone (`git worktree prune` owns that), and any worktree the sweep cannot prove idle, unlocked, idle in `lsof`, and fully captured on origin, or byte-identical in the main checkout for DEC-S paths. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)
- Inputs: `git worktree list --porcelain -z` records (`worktree`, `HEAD`, `branch` or `detached`, optional `locked <reason>` and `prunable <reason>`, sampled in `## Grounding`); the knob `wrap.archive_worktree_min_age_hours` through `kit_config_get_root` (root-only, default `72`).
- New flag: `wrap.sh apply --archive-worktrees`. It combines with every `apply` flag except `--pull-only` (exit 64, `wrap.sh apply: --pull-only cannot combine with --archive-worktrees`).
- Section header: `-- archive worktrees:`, printed after `-- archive unmerged:` and before `-- origin branches:`. With the flag off, no section prints and the report is byte-identical to today.
- Report lines, each indented five spaces like the other sections:
  - `SKIP archive worktrees: --own scopes cleanup to the named worktrees`
  - `SKIP archive worktrees: --no-pull (a step 0 stop; other sessions' worktrees stay)`
  - `SKIP archive worktrees: no origin remote`
  - `SKIP archive worktrees: fetch failed, stale data`
  - `SKIP archive worktrees: busy check unavailable (no lsof, or KIT_WRAP_SKIP_BUSY_CHECK=1)`
  - `SKIP archive worktrees: wrap.archive_worktree_min_age_hours=<v> is not a whole number >= 1` (sets FAILURES)
  - `SKIP <wt>: unresolvable` / `SKIP <wt>: prunable (<reason>)`
  - `SKIP <wt>: wrap runs from inside it` / `SKIP <wt>: <b> is the main checkout's branch`
  - `SKIP <wt>: <b> is the default or a protected branch name`
  - `SKIP <wt>: <b> proven merged (<proof>), left for --worktrees`
  - `<wt>: nothing unique, left alone`
  - `SKIP <wt>: fresh, idle <h>h < <min>h (wrap.archive_worktree_min_age_hours)`
  - `SKIP <wt>: locked by live pid <pid> (an agent is still running)`
  - `SKIP <wt>: busy, held by pid <pid> (<command>)` (the existing `BUSY_MSG`)
  - `SKIP <wt>: index.lock held in the worktree`
  - `SKIP <wt>: holds an initialized submodule (<path>)`
  - `SKIP <wt>: a merge, rebase, cherry-pick, revert or bisect is in progress`
  - `SKIP <wt>: unmerged index or unborn HEAD (nothing to snapshot safely)`
  - `SKIP <wt>: <n> ignored paths would be lost, first <path> (never pushed, never deleted)`
  - `SKIP <wt>: holds an embedded git repository (<path>)` (from `git status` before the snapshot, or a new gitlink in the snapshot tree after it)
  - `SKIP <wt>: uncommitted <path> looks like a secret (never pushed)` (from `git status` in the dry run; from `diff-tree` on the staged and snapshot trees under `--apply`)
  - `WOULD archive worktree <wt> [<b>|detached, <n> unique commits, <k> uncommitted paths, idle <h>h] -> origin archive/<slug>-<date>, then remove it`
  - `archived worktree <wt> -> archive/<slug>-<date> (<sha7>); removed[, <b> deleted]`
  - `kept <wt>: archived to <ref>, but it changed during the push (the ref holds the earlier state)`
  - `kept <wt>: archived to <ref>, but <b> was checked out elsewhere during the push`
  - `FAILED archive worktree <wt>: origin <ref> already exists`
  - `FAILED archive worktree <wt>: <first push error line>`
  - `FAILED archive worktree <wt>: origin <ref> holds <sha7>, not the archive tip <sha7>`
  - `FAILED archive worktree <wt>: snapshot failed (<first error line>)`
  - `FAILED archive worktree <wt>: <wt> survived the removal, <b> not deleted`
  - `FAILED archive worktree <wt>: removed, but the local delete of <b> refused` (the leased `update-ref -d` failed: <b> moved since HEAD was read)
- Exit code: unchanged contract. Any FAILED sets FAILURES and `apply` exits 2. SKIP and `kept` lines do not.
- Invariants:
  - The worktree's own index, HEAD, branch ref and files are never written before origin holds the archive tip.
  - A dry run writes nothing, objects included: it reads `git status`, `git cherry` and mtimes, and never runs `git add`.
  - Gitignored files are never pushed. A non-regenerable one blocks the removal.
  - No UNCOMMITTED path (untracked, modified, staged-added or renamed-to) whose basename matches `_ARCHIVE_SECRET_GUARD` is ever pushed. Paths already in the worktree's commits are not scanned (DEC-L).
  - No embedded repository (an untracked directory, at any depth, holding its own `.git`) is ever removed: its objects never reach origin through a gitlink.
  - Every `git status` read in the sweep passes `--no-optional-locks`, so the sweep never rewrites a worktree's index (which would also reset its idle age).
  - The push is never forced: the only push form is the create-only lease.

### Data model changes
None in the kit. On origin, new `refs/heads/archive/<slug>-<YYYYMMDD>` refs, the same namespace `--archive-unmerged` writes.

### API changes (endpoints, request/response shapes)
One CLI flag on `wrap.sh apply`, one root-only knob, both above.

### UI changes (screens, components, interactions)
None.

### Infrastructure changes
None.

## Task Breakdown

### Phase 1: Shared helpers
Dependencies: A, A2, B, C and H stand alone. D and E1 land together (D calls the function E1 creates). E2 needs A, A2, B, C and E1. F1 needs C and E2. F2 needs F1. Each G task needs the code tasks named on it. A code task and the G task that holds its cases close together, in one commit: the code task's acceptance IS those cases green.

- [ ] TASK-A: Extract the matcher body of `_land_ignored_allowed` into `_ignored_match <path> <entries>` in `lib/wrap/wrap-common.sh`. `_land_ignored_allowed` calls it with `${_LAND_IGNORED_BUILTIN} $(kit_config_get_root wrap.land_ignored_allow "")`. Acceptance: behavior-preserving; `bash tests/test-wrap-land.sh` stays green with no test edited.
- [ ] TASK-A2: Add one shared constant `_ARCHIVE_SECRET_GUARD` in `lib/wrap/wrap-common.sh`, a space-separated basename glob list: `.env* *.pem *.key *secret* *credential* *token* id_rsa* id_ed25519* id_ecdsa* id_dsa* *.p12 *.pfx *.jks *.keystore .npmrc .netrc .pgpass *.kdbx auth.json *password* *passwd* .dev.vars .envrc`, and `_secret_shaped <path>` that matches the path's basename against it (case-insensitive, under `set -f`). `wrap-land.sh:366` uses it for its "looks like a secret" hint. Acceptance: `bash tests/test-wrap-land.sh` green; `archive_wt_secret_untracked`, `archive_wt_secret_id_rsa`.
- [ ] TASK-B: Add `_wt_idle_secs <wt>` and `_wt_ignored_blockers <wt>` to `lib/wrap/wrap-apply.sh`. `_wt_idle_secs` reads the reflog entry time and the admin dir (`git -C <wt> rev-parse --path-format=absolute --git-dir`) per the idle-age term, reads status with `--no-optional-locks status --porcelain=v1 -z --untracked-files=all`, and uses `_mtime`. A future mtime counts as age 0. `_wt_ignored_blockers` reads `--no-optional-locks status --porcelain -z --ignored=matching --untracked-files=all`, keeps `!!` entries, strips a trailing `/`, and prints each path `_ignored_match` does not cover with `_ARCHIVE_IGNORED_REGENERABLE` (`node_modules .wrangler dist *.tsbuildinfo __pycache__ target .pytest_cache/ .venv/ .mypy_cache/ .ruff_cache/ .DS_Store tests/.cache .claude/session-state`). One more class counts as regenerable: an ignored path under `.claude/` whose every file is byte-identical (`cmp`) to the file at the same relative path in the main checkout (DEC-S). Acceptance: cases `archive_wt_claude_synced`, `archive_wt_fresh_by_dirty_mtime`, `archive_wt_ignored_blocks`, `archive_wt_regenerable_ok`.
- [ ] TASK-C: Add `_wt_snapshot <wt>`. It copies the admin `index` (or starts from `read-tree HEAD` when there is none) to a `mktemp` file, writes the staged tree from that copy, runs `env GIT_INDEX_FILE=<abs tmp> git -C <wt> add -A`, writes the snapshot tree, and builds the staged commit (only when the staged tree differs from both HEAD's tree and the snapshot tree) and the snapshot commit with `commit-tree`. A clean worktree returns HEAD as the tip. It removes its temp file. Acceptance: case `archive_wt_dirty_snapshot`; the worktree's `status --porcelain` and HEAD are byte-identical before and after.

### Phase 2: The sweep
- [ ] TASK-D: Parse `--archive-worktrees` in `cmd_apply` (global `ARCHIVE_WORKTREES=0` beside `ARCHIVE_UNMERGED` in `wrap-common.sh`). Refuse it with `--pull-only` (exit 64). Call `_apply_archive_worktrees` from `_apply_repo` right after the `--archive-unmerged` call. Acceptance: `archive_wt_pull_only_refused`, `archive_wt_flag_off_no_section`.
- [ ] TASK-E1: Write `_apply_archive_worktrees` up to the record guards: the section-level skips (`--own`, `--no-pull`, no origin, fetch failed, bad knob, busy check unavailable: no `lsof` on PATH or `KIT_WRAP_SKIP_BUSY_CHECK=1`), then the loop over whole records (it collects every attribute up to the record's empty NUL terminator, unlike `_apply_worktrees`, which acts on the `worktree` line alone), then per record: prunable (from the record), unresolvable, main checkout (silent), invoking worktree (canonical `$PWD` at or under the worktree, or its branch equal to `cur`), protected branch, in-progress operation (admin `MERGE_HEAD`, `rebase-merge/`, `rebase-apply/`, `CHERRY_PICK_HEAD`, `REVERT_HEAD` or `BISECT_LOG` present), unmerged index or unborn HEAD (any `DD`, `AU`, `UD`, `UA`, `DU`, `AA` or `UU` status code, or a failing `rev-parse --verify -q HEAD`; G4d's AC-35 and G5's AC-36 hold the cases for this guard and the busy skip). Acceptance: `archive_wt_own_and_nopull`, `archive_wt_knob`, `archive_wt_prunable`, `archive_wt_protected`, `archive_wt_sequencer`.
- [ ] TASK-E2: The candidate and safety guards, in this order: candidate test (`git cherry`, or dirty), merge proof (branch-held and clean only), staleness, live lock pid, busy, worktree `index.lock` (`_write_guard <wt>`), initialized submodule (a mode-160000 entry in `ls-files -s` whose path holds a `.git`), embedded repository, ignored blockers, secret-shaped uncommitted path. The embedded and secret guards share ONE read, `--no-optional-locks status --porcelain=v1 -z --untracked-files=all`: in `all` mode git lists untracked files one by one but stops at a nested repo and prints its directory with a trailing `/` (sampled: `?? outer/inner/`), so the embedded guard flags every `??` entry ending in `/` whose path holds a `.git` file or directory, at any depth; the secret guard runs `_secret_shaped` on every untracked, added, modified and renamed-to path of the same read (a rename record carries two paths). Then the dry-run `WOULD archive worktree` line and `continue`. Acceptance: `archive_wt_dry_run`, `archive_wt_fresh`, `archive_wt_merged_left`, `archive_wt_embedded_repo`, `archive_wt_embedded_repo_deep`.
- [ ] TASK-F1: The push half. `_write_guard <repo>`; read HEAD; pre-read the ref with `ls-remote --exit-code --heads origin <ref>` (FAILED when present); `_wt_snapshot`; the two tree guards (DEC-H, DEC-I): the gitlink guard lists `ls-tree -r` mode-160000 entries of the snapshot tree and of HEAD's tree as `<path> <sha>` pairs, and any snapshot pair absent from HEAD's set (a new path, or a known path at a new sha) is `SKIP ... embedded git repository`; the secret guard runs `_secret_shaped` on every name `git diff-tree -r --name-only -z HEAD <tree>` prints, for the staged tree and the snapshot tree, as `SKIP ... looks like a secret`; either skip pushes nothing; push with the create-only lease; read back with `ls-remote` and compare to the tip (FAILED on a mismatch). Acceptance: `archive_wt_lease_form`, `archive_wt_dirty_snapshot`, `archive_wt_secret_staged`.
- [ ] TASK-F2: The removal half. Re-read HEAD and recompute the snapshot tree (`kept` on any change); re-check the live lock and busy; `git worktree remove -f -f`; `_wt_cleared` (FAILED when the path survives); for a branch-held worktree, re-check the branch is not checked out anywhere (`kept` when it is), then `update-ref --no-deref -d refs/heads/<b> <HEAD>` (the HEAD read in F1, never the archive tip) and `config --remove-section branch.<b>`; a refused delete is the `removed, but the local delete of <b> refused` FAILED line. Acceptance: `archive_wt_branch_apply`, `archive_wt_changed_during_push`.

### Phase 3: Tests and docs
All G tasks write into one new section `=== apply --archive-worktrees ===` in `tests/test-wrap-apply.sh`, one case per AC row, on a fresh bare origin plus clone per case like `build_au_repo`. Worktrees are aged by creating their commits and checkouts under `GIT_COMMITTER_DATE=2026-01-01T00:00:00` (the reflog entries take that time) and by `touch -t 202601010000` on the admin `HEAD`, `commondir` and any dirty path. G1 writes the shared fixture builder; G2 to G5 reuse it.

- [ ] TASK-G1 (needs C, D, E2, F1, F2): the fixture builder `build_aw_repo` and the dry-run and apply cases: AC-1, AC-2, AC-3, AC-4, AC-5. Acceptance: those five cases green; each control red.
- [ ] TASK-G2 (needs B, E2, G1): freshness and busy: AC-6, AC-7, AC-8, AC-9, AC-34. Acceptance: those five cases green; each control red.
- [ ] TASK-G3 (needs F1, F2, G1): push, lease, change during push: AC-10, AC-11, AC-15, AC-16. Acceptance: those four cases green; each control red.
- [ ] TASK-G4a (needs A, A2, B, E2, F1, F2, G1): ignored and secret paths: AC-12, AC-13, AC-14, AC-32, AC-37. Acceptance: those cases green; each control red.
- [ ] TASK-G4c (needs A2, E2, F1, G1): embedded repos and the staged secret: AC-30, AC-30b, AC-31. Acceptance: those cases green; each control red.
- [ ] TASK-G4b (needs E1, E2, G1): merge proof, nothing unique, protected, submodule, prunable: AC-17, AC-18, AC-23, AC-24, AC-25. Acceptance: those cases green; each control red.
- [ ] TASK-G4d (needs E1, F2, G1): sequencer, unmerged or unborn, and invoking worktree: AC-29, AC-33, AC-35. Acceptance: those cases green; each control red.
- [ ] TASK-G5 (needs D, E1, G1): flags, knob and busy-check availability: AC-19, AC-20, AC-21, AC-22, AC-36. Acceptance: those cases green; each control red.
- [ ] TASK-H: Docs. `lib/wrap/wrap.sh` header: the usage line, a paragraph for the flag, and the closed write set (one temporary-index object write per dirty worktree, one create-only leased push per worktree, one `worktree remove -f -f`, one leased `update-ref -d`); widen `_usage`'s `sed -n '2,42p'` range to the new header end. `commands/wrap.md` step 5: one bullet for `--archive-worktrees` (opt-in, never in the default flow, never with `--own`), and the "Never remove a dirty or foreign worktree" bullet names this flag as the one exception, after the snapshot lands on origin. `kit.toml` `[wrap]`: the knob with its comment. `CHANGELOG.md`: one entry. TASK-H writes its own two cases into the G section (AC-26, AC-27; they need only G1's section header). Acceptance: `archive_wt_usage_names_flag`, `archive_wt_wrap_md_bullet`.

## After state
- [ ] `bin/wrap apply --archive-worktrees <repo>` previews each stale unmerged or detached worktree with a `WOULD archive worktree` line. (Today: the flag does not exist; such worktrees appear only as `SKIP` lines under `--worktrees`.)
- [ ] `bin/wrap apply --apply --archive-worktrees <repo>` leaves origin holding `archive/<slug>-<date>` at the archive tip, and the worktree and its branch gone, checkable by `git ls-remote origin 'refs/heads/archive/*'` and `git worktree list`.
- [ ] A dirty archived worktree's uncommitted files are readable on origin, checkable by `git show origin/archive/<slug>-<date>:<path>` after a fetch.
- [ ] A worktree idle less than the knob, locked by a live pid, or busy in `lsof` is never pushed or removed, checkable by the `fresh`, `live_lock` and `busy` cases.
- [ ] `commands/wrap.md` names the flag in step 5, checkable by `grep -c -- '--archive-worktrees' commands/wrap.md` >= 1.

## Quality requirements
none (the repo has no `docs/QUALITY.md`).

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] The AC table below is green, and each negative control turns its case red
- [ ] No regressions in `tests/test-wrap-apply.sh` and `tests/test-wrap-land.sh`

### AC table

| AC | Criterion | Test case (section `archive-wt`) | Negative control (mutation, expected red) |
|---|---|---|---|
| AC-1 | dry run on a stale branch-held unmerged clean worktree prints `WOULD archive worktree`, exit 0; worktree, branch and origin unchanged | `archive_wt_dry_run` | make the dry-run branch fall through to the push: origin gains the ref, case red |
| AC-2 | dry run on a stale dirty worktree writes no object (`count-objects -v` `count` and `in-pack` unchanged) | `archive_wt_dry_run_no_objects` | call `_wt_snapshot` before the `APPLY` check: loose count grows, case red |
| AC-3 | apply on a stale branch-held unmerged clean worktree: origin ref equals the branch tip, worktree path gone, branch and `branch.<b>` config gone | `archive_wt_branch_apply` | drop the `update-ref -d` call: branch survives, case red |
| AC-4 | apply on a stale detached worktree with a commit origin lacks: origin ref equals its HEAD, worktree gone | `archive_wt_detached_apply` | restore the `detached HEAD` skip from `_apply_worktrees` in the new loop: nothing pushed, case red |
| AC-5 | apply on a stale dirty branch-held worktree (one modified tracked file, one untracked file, one file staged then edited): origin ref tree holds the disk version of all three; the staged version is in the ref's first parent; worktree gone; the local branch gone (its delete leased to HEAD, not the snapshot tip) | `archive_wt_dirty_snapshot` | build the snapshot from `HEAD` alone: `git show <ref>:w.txt` fails, case red |
| AC-6 | a just-created worktree with an unmerged commit is `SKIP ... fresh`; nothing pushed, worktree kept | `archive_wt_fresh` | delete the staleness check: origin gains the ref, case red |
| AC-7 | admin files aged, an untracked file touched now: `SKIP ... fresh` | `archive_wt_fresh_by_dirty_mtime` | drop the dirty-path mtimes from `_wt_idle_secs`: archived, case red |
| AC-8 | a lock naming a live pid (a background `sleep`): `SKIP ... locked by live pid`; nothing pushed | `archive_wt_live_lock` | delete the live-lock check: archived, case red |
| AC-9 | a background process with its cwd in the worktree: `SKIP ... busy`; nothing pushed | `archive_wt_busy` | delete the busy check: archived, case red |
| AC-10 | an existing `archive/<slug>-<date>` on origin at an ANCESTOR of the tip: `FAILED ... already exists`, exit 2, worktree and branch kept, origin ref unchanged | `archive_wt_ref_exists` | delete the pre-read and replace the lease with a plain push: origin fast-forwards, case red |
| AC-11 | the archive push carries the create-only lease: with `GIT_TRACE=<file>` set, the traced `git push` argv holds `--force-with-lease=refs/heads/archive/<slug>-<date>:` | `archive_wt_lease_form` | replace the lease with a plain push: the trace has no lease argument, case red |
| AC-12 | an ignored `.env` in the worktree: `SKIP ... ignored paths would be lost, first .env`; nothing pushed, `.env` still on disk | `archive_wt_ignored_blocks` | make `_wt_ignored_blockers` print nothing: archived and `.env` deleted, case red |
| AC-13 | only an ignored `node_modules/`: archived and removed | `archive_wt_regenerable_ok` | drop `node_modules` from the regenerable list: SKIP, case red |
| AC-14 | an untracked, not ignored `.env.local`: `SKIP ... looks like a secret`; origin has no ref | `archive_wt_secret_untracked` | delete the secret check: origin ref holds `.env.local`, case red |
| AC-15 | a pre-push hook appends a line to a tracked file in the worktree: `kept ... changed during the push`; worktree exists; origin ref holds the pre-change content | `archive_wt_changed_during_push` | delete the post-push tree recompute: worktree removed and the line lost, case red |
| AC-16 | a pre-push hook that exits 1: `FAILED archive worktree <wt>: <hook line>`, exit 2, worktree kept, `-- pull:` still printed | `archive_wt_push_refused` | remove both guards between the push and the removal (the push-failure branch and the read-back compare): the remove runs and the worktree is gone, case red |
| AC-17 | a clean branch worktree whose two commits landed on origin/main as one squash commit (the ABSORBED proof; `git cherry` still shows `+`): `SKIP ... proven merged ..., left for --worktrees` | `archive_wt_merged_left` | delete the merge-proof check: a create-only push of a merged tip happens, case red |
| AC-18 | a clean detached worktree at origin/main: `<wt>: nothing unique, left alone` | `archive_wt_nothing_unique` | invert the cherry count test: archived, case red |
| AC-19 | `--own <x>` and `--no-pull` each print their section SKIP and archive nothing | `archive_wt_own_and_nopull` | delete the `--own` skip: the sweep previews a worktree, case red |
| AC-20 | `--pull-only --archive-worktrees` exits 64 naming the flag | `archive_wt_pull_only_refused` | delete the conflict check: exit 0, case red |
| AC-21 | the flag off: no `archive worktrees` text in the report | `archive_wt_flag_off_no_section` | call the sweep unconditionally: the header prints, case red |
| AC-22 | root `kit.toml` `archive_worktree_min_age_hours = 100000` makes a worktree aged to 2026-01-01 fresh; a project `.kit.toml` value of `1` is ignored; a value `abc` prints the knob SKIP and exits 2 | `archive_wt_knob` | read the knob with `kit_config_get` (project-aware): the project value wins, case red |
| AC-23 | a worktree on a branch named `master` with one commit, in a repo whose default is `main`, is never a candidate | `archive_wt_protected` | delete the protected-name check: `WOULD archive` prints, case red |
| AC-24 | an initialized submodule in the worktree: `SKIP ... initialized submodule` | `archive_wt_submodule` | delete the submodule check: archived, case red |
| AC-25 | a prunable record (directory moved away): `SKIP ... prunable` | `archive_wt_prunable` | delete the prunable check: `SKIP ... unresolvable` prints instead, case red on the exact text |
| AC-30 | an untracked nested clone (`?? nested/` with `nested/.git`) in a stale dirty worktree: `SKIP ... embedded git repository (nested)` in the dry run and under `--apply`; nothing pushed, `nested/.git` still on disk | `archive_wt_embedded_repo` | delete only the status guard: the dry run prints `WOULD archive worktree` for this fixture, case red on the dry-run verdict |
| AC-30b | a nested clone below an untracked directory (`outer/inner/.git`, with `outer/f.txt` beside it): the same SKIP naming `outer/inner/` in the dry run and under `--apply`; nothing pushed, `outer/inner/.git` still on disk | `archive_wt_embedded_repo_deep` | read the status with `--untracked-files=normal`: the entry collapses to `?? outer/` (no `.git` at that level), the dry run prints `WOULD archive worktree`, case red |
| AC-31 | a staged-added `.env` (`git add -f .env`, so status shows `A  .env` while it stays ignored on disk): `SKIP ... .env looks like a secret`; origin has no ref | `archive_wt_secret_staged` | drop both `diff-tree` checks and limit the status check to `??` entries: the staged and snapshot commits carry `.env` to origin, case red |
| AC-32 | an untracked, not ignored `id_rsa`: `SKIP ... id_rsa looks like a secret`; origin has no ref | `archive_wt_secret_id_rsa` | revert `_ARCHIVE_SECRET_GUARD` to the old land pattern: `id_rsa` reaches origin, case red |
| AC-33 | `wrap apply --archive-worktrees` run with its cwd inside a stale candidate worktree: `SKIP <wt>: wrap runs from inside it`; nothing pushed | `archive_wt_invoking_wt` | delete the invoking-worktree guard: the busy check exempts wrap's own ancestors, so the worktree is archived and removed under the caller, case red |
| AC-34 | a worktree aged through `GIT_COMMITTER_DATE` and `touch -t`, then `git reflog expire --all` (which empties the aged reflog and sets `logs/HEAD` mtime to now): still stale, `WOULD archive worktree` | `archive_wt_stale_after_reflog_expire` | read the admin component from the `logs/HEAD` mtime: the worktree reads fresh, case red |
| AC-35 | a stale worktree with a `UU` path (a conflicting `stash pop`), and a stale worktree on an unborn branch: each `SKIP ... unmerged index or unborn HEAD`, exit 0, nothing pushed | `archive_wt_unmerged_unborn` | delete the guard: `write-tree` fails, the line is `FAILED ... snapshot failed`, exit 2, case red |
| AC-36 | `KIT_WRAP_SKIP_BUSY_CHECK=1`, and a PATH without `lsof`: each prints the section SKIP `busy check unavailable` and archives nothing | `archive_wt_busy_unavailable` | delete the section skip: `_wt_busy` answers "not busy" and the stale fixture is archived, case red |
| AC-37 | (a) a stale unmerged worktree whose only ignored path is `.claude/rules/x.md`, identical to the main checkout's copy, is archived and removed; (b) the same with one differing file under `.claude/` prints `SKIP ... ignored paths would be lost` and keeps the file on disk | `archive_wt_claude_synced` | make the DEC-S class accept any `.claude/` path: case (b) is archived and the differing file is deleted, case red |
| AC-29 | a stale detached worktree stopped mid-rebase (admin `rebase-merge/` present): `SKIP ... in progress`; nothing pushed | `archive_wt_sequencer` | delete the in-progress check: the partial state is archived, case red |
| AC-26 | `wrap.sh --help` names `--archive-worktrees` | `archive_wt_usage_names_flag` | leave `_usage`'s sed range at `2,42`: the new line is cut, case red |
| AC-27 | `commands/wrap.md` step 5 carries the `--archive-worktrees` bullet and the exception in the never-remove bullet | `archive_wt_wrap_md_bullet` | remove the bullet: case red |
| AC-28 | `land`'s ignored-file guard is unchanged after the extraction | the existing `tests/test-wrap-land.sh` ignored cases | n/a, existing cases stay green |

## Verification
The exact commands:

```
bash tests/test-wrap-apply.sh
bash tests/test-wrap-land.sh
bash tests/run-all.sh --changed origin/master
```

Each negative control runs on a mutated copy of `lib/wrap/wrap-apply.sh` (or `wrap.sh`, `commands/wrap.md` for AC-26, AC-27) in a scratch worktree through `lib/gate/negctl.sh`, after the branch is committed, and the named case must go red.

## Edge Cases
1. Two worktrees whose slugs collide on the same day (a branch `feat/x` and a detached worktree named `feat-x`): the first archives; the second is `FAILED ... already exists` and stays. The next day's run archives it under a new date.
2. A worktree archived, then re-created by hand the same day and archived again: `FAILED ... already exists`. The archive ref is never overwritten; the operator renames or waits a day.
3. A branch-held worktree whose branch also exists on origin under its own name, clean, not merged: still archived. The archive ref is the stable record; the own-name origin branch is not touched.
4. A file staged with content X, then edited on disk to Y: the staged commit holds X, the snapshot holds Y. Neither is lost.
5. An untracked file larger than the remote accepts (GitHub refuses over 100 MB): the push fails, `FAILED ... <first error line>`, the worktree stays. The loose objects the snapshot wrote are left for `git gc`.
6. `user.name` or `user.email` unset: `commit-tree` fails, `FAILED ... snapshot failed`, nothing pushed, worktree kept.
7. A clock skew puts a dirty file's mtime in the future: its age counts as 0, so the worktree reads fresh. Safe side.
8. A worktree locked with a reason that names a dead pid, or no pid: the lock is no skip reason (as in `_apply_worktrees`); `-f -f` overrides it once every other guard passed.
9. A worktree path holding a newline: the loop reads `-z` records, like `_apply_worktrees`.
10. The fetch failed: the section skips, because the cherry and merge proof would read stale data.
11. Guarantee inversion: "never removed before origin holds the tip" holds only because the `ls-remote` comparison sits between the push and the removal. AC-16 and its control pin the order; AC-15 pins the post-push re-read.
12. Guarantee inversion: "a dry run writes nothing" holds only because `_wt_snapshot` runs after the `APPLY` check. AC-2 pins it.
13. Guarantee inversion: "fresh worker worktrees are never touched" rests on three independent checks (idle age, live lock pid, `lsof`). AC-6 to AC-9 pin each one alone.
14. The main checkout sits on a feature branch that a worktree also references: git refuses that state, so no candidate can hold the main checkout's branch; the protected and main-checkout checks still run.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Push refused (hook, protection, permission, size) | `FAILED archive worktree <wt>: <first line>`, exit 2 | Nothing removed. Fix the cause and re-run; the same-day ref does not exist yet. |
| Push landed, read-back disagrees | `FAILED ... origin <ref> holds X, not the archive tip Y` | Nothing removed. Inspect the ref by hand; a racing writer is the likely cause. |
| Worktree changed during the push | `kept <wt>: ... changed during the push` | The ref holds the earlier state; the worktree keeps the newer one. Next day's run archives again under a new date. |
| Removal partly failed (read-only parent) | `FAILED ... survived the removal` | Branch kept. The archive ref already holds everything; remove by hand once fixed. |
| Ignored non-regenerable file present | `SKIP ... ignored paths would be lost` | Never pushed (may be a secret), never deleted. The operator moves the file and re-runs. |
| Lock pid owned by another user | `kill -0` fails with EPERM, so `_wt_lock_live` reads a live pid as dead | Blind spot, accepted: the lock is then overridden like a dead one. The `lsof` busy check still runs and is required (DEC-R), but it sees another user's open files only with enough privilege, so a cross-user worker can be missed. |
| A live worker the three checks all miss | a worker reports its directory vanished | The archive ref holds the worker's state at the push; `git worktree add <path> <ref>` restores it. |
| Embedded repository in the worktree (a nested clone or worktree, untracked) | `SKIP ... embedded git repository (<path>)` | Never pushed as a bare gitlink, never removed. The operator pushes or moves the nested repo, then re-runs. |
| Snapshot captured an unexpected large file | push refused by size, or a large archive ref | Push refusal keeps the worktree. A landed large ref is deleted on origin by hand. |

## Out of Scope
- Changing the existing `--archive-unmerged` push to the create-only lease. Its pre-read leaves the same fast-forward race this spec closes for worktrees; a separate change can adopt the lease there.
- The existing `--worktrees` sweep deleting ignored files on removal (sampled in `## Grounding`). It only removes proven-merged clean worktrees; a guard there is a separate change.
- Deleting or expiring `archive/*` refs on origin.
- Pruning registry entries whose directory is gone (`git worktree prune`).
- Reporting archive candidates in `wrap scan`.
- Running the sweep from `/kit:wrap`'s default step 5 flow. The operator asks for it by name.

## Touches
- lib/wrap/**
- commands/wrap.md
- tests/test-wrap-apply.sh
- kit.toml

## Decision Log
- DEC-A: a new flag, not a widened `--archive-unmerged` or `--worktrees`. Reason: both existing flags have callers that never asked for unmerged worktree removal, and `--worktrees` runs on every default wrap. Rejected: widen either.
- DEC-B: dirty worktrees ARE archived, through a snapshot commit built from a temporary index. Reason: the hand procedure did exactly this, and a stale dirty worktree is the most common pile-up. The worktree's own index and HEAD are never written, so a failure anywhere before the removal leaves the worktree as it was. Rejected: skip every dirty worktree (the pile-up stays); `git stash create` (no untracked files); commit inside the worktree (writes the worktree's branch and index before origin holds anything).
- DEC-C: the push is a create-only lease, plus the existing pre-read for a clear message. Reason: a plain push fast-forwards an existing archive ref (sampled), and the pre-read alone leaves the window between the pre-read and the push's own ref advertisement. After the advertisement, receive-pack's own compare refuses either form. Rejected: plain push (the race); `--force` (never).
- DEC-D: staleness is a root-only knob, default 72 hours, minimum 1, measured from admin and dirty-path mtimes, not the admin `index`. Reason: a plain `git status` from any tool rewrites the index mtime (sampled), so it would keep every worktree fresh forever. The HEAD commit date is rejected too: a fresh worktree made from an old origin commit would read stale. Root-only because the knob widens a remote write, the same fence as every other `wrap.*` write knob.
- DEC-E: ignored files are never pushed, and a non-regenerable one blocks the removal. Reason: ignored files are often secrets (`.env`), so pushing them leaks; deleting them may lose the only copy. Rejected: allow-list knob now (no caller asked; add it when one does).
- DEC-F: candidates use `git cherry origin/<default> <HEAD>` for clean worktrees, the same test `--archive-unmerged` uses, and the merge proof hands clean merged worktrees to `--worktrees`. A dirty worktree is always a candidate, merged or not, because its snapshot is unique. Rejected: "tip not on any origin ref" (a branch pushed under its own name would never archive, and the pile-up stays).
- DEC-H (validation round 1, critical): an embedded repository blocks the archive. `git add -A` records an untracked directory holding its own `.git` as a gitlink only (sampled: `160000 commit <sha> nested`), so its objects never reach origin, and `-f -f` then deletes it. Two guards: a status scan before the snapshot (visible in the dry run) and a new-gitlink scan of the snapshot tree after it. The existing submodule guard reads the real index and misses this shape. Rejected: push the nested repo too (a second remote write into an unknown repo).
- DEC-I (validation round 1, critical): the secret check is one shared, widened constant `_ARCHIVE_SECRET_GUARD`, run twice: on `git status` paths in the dry run, and on `diff-tree` names of the staged and snapshot trees right before the push. The push is the one irreversible step, so the check reads exactly what will leave. Land's hint uses the same list. Rejected: the land pattern as is (misses keys, keystores, `.netrc`, `.npmrc`, password files); a status-only check (misses a staged-added file that is ignored on disk).
- DEC-J (validation round 1, critical): TASK-E and TASK-G split along the guard order and the AC groups, with declared dependencies, so each task fits one session.
- DEC-K (validation round 1, folded warnings): the branch delete is leased to the HEAD read before the push, not the archive tip (they differ when dirty); AC-11 asserts the lease form through `GIT_TRACE`, because receive-pack already refuses a ref created after its advertisement, so a race fixture cannot tell a lease from a plain push; the invoking worktree is never a candidate. Its `cur` half (the worktree's branch equal to the main checkout's) mirrors the `wtb = cur` skip in `_apply_worktrees`; its `$PWD` containment half is new code, because `_wt_busy` exempts wrap's own ancestors and would otherwise let wrap remove the directory it runs from (round 2 correction).
- DEC-L (validation round 2, critical fold of the secret overclaim): the secret guard covers UNCOMMITTED paths only. Commits the worktree already holds push unscanned, exactly as `--archive-unmerged` pushes a branch today; this is an accepted risk. Rejected: scan `diff-tree -r --name-only --diff-filter=AR -z <merge-base origin/<def> tip> <tip>` (it would SKIP every worktree whose history ever added a file like `tokenizer.py`, so worktrees pile up again, and it still misses a secret added then removed inside the range; committed history is the author's own deliberate write).
- DEC-M (validation round 2, critical): the embedded guard reads status with `--untracked-files=all`, shared with the secret read. `normal` mode collapses `outer/inner/.git` to `?? outer/`, which holds no `.git`, so the round-1 guard let a depth-2 nested repo through and the dry run printed `WOULD archive`. In `all` mode git stops at the nested repo and prints `?? outer/inner/` (sampled). The gitlink tree guard compares `<path> <sha>` pairs, not paths alone. It is a backstop: no fixture reaches it with the status guard intact, so it has no isolated control (see `## Grounding`).
- DEC-O (validation round 3, critical): the header is `Depth: blind-spot`, naming the gitlink tree guard's missing isolated control. The full test-plan review team runs for this spec. Rejected: `standard` (the spec itself lists failures no single case can catch).
- DEC-P (validation round 3, must-address): the admin part of idle age is the newest reflog entry's own time (`log -g -1 --date=unix --format=%gd`), plus the admin `HEAD` and `commondir` mtimes; never the `logs/HEAD` mtime, which `git reflog expire` and `gc --auto` set to now (sampled). The suggested `--format=%ct` is rejected: it prints the commit's committer date, so a fresh worktree checked out at an old commit would read stale (sampled: `%ct` 1793442113 vs selector `{1767200400}` on a just-created worktree). An empty reflog falls back to the two admin mtimes.
- DEC-Q (validation round 3, must-address): an unmerged index or an unborn HEAD is a SKIP before the snapshot. Without it, `write-tree` or `commit-tree -p HEAD` fails on every run, so the worktree reports FAILED and exit 2 forever.
- DEC-R (validation round 3, must-address): the busy check is required. With no `lsof` or `KIT_WRAP_SKIP_BUSY_CHECK=1`, the whole section skips, unlike `--worktrees`, which proceeds without it: this sweep pushes and removes unmerged work, so it fails closed. The cross-user pid blind spot is a Failure modes row.
- DEC-S (validation round 3, must-address): an ignored path under `.claude/` is regenerable when every file in it is byte-identical to the same relative path in the main checkout. Live worktrees carry `.claude/rules/` copied from the main checkout (sampled), and the main checkout keeps the canonical copy, so removing the worktree loses nothing. A differing or extra file still blocks. Rejected: keep the SKIP (it would skip most real worktrees, so the pile-up stays); add `.claude/` wholesale (a hand-edited rule file there would be lost).
- DEC-T (validation round 4, critical): DEC-S gets its own AC (AC-37, owned by TASK-B and G4a) with a control that widens the class to any `.claude/` path; the Terms entry, the Boundaries line and the Picture name the DEC-Q, DEC-R and DEC-S guards. No fifth round: the operator directed the build.
- DEC-N (validation round 2, critical): TASK-E1 drops the invoking-worktree case (G4d owns AC-33); TASK-F splits into F1 (push half) and F2 (removal half); the G tasks split to at most five cases each (G4a, G4b, G4c, G4d, G5), and AC-26 and AC-27 move to TASK-H alone. D and E1 land together, and a code task closes in the same commit as the G task holding its cases.
- DEC-G: skipped under `--own` and `--no-pull`. Reason: both mean "this session's scope only" or "a foreign writer is live"; an unscoped sweep over other sessions' worktrees contradicts both.

## Grounding

Every external shape below was sampled read-only against a scratch repo built under this run's own scratch dir (`mktemp -d .../scratchpad/wtsample.XXXXXX`, a bare origin plus a clone), never a real repo. `git version 2.56.0`.

- `git worktree list --porcelain` for a detached, a branch-held, and a locked worktree (paths shortened to `<S>`):

  ```
  worktree <S>/clone
  HEAD 3fed0c0381f6c0b1302565a74a46f2339a514d7f
  branch refs/heads/main

  worktree <S>/clone/.claude/worktrees/det
  HEAD 0ae5ef71a04b6ceb2a763c073696e19669cf909e
  detached

  worktree <S>/clone/.claude/worktrees/dirty
  HEAD 3fed0c0381f6c0b1302565a74a46f2339a514d7f
  branch refs/heads/feat/dirty
  locked claude agent abc (pid 99999 start x)

  worktree <S>/clone/.claude/worktrees/held
  HEAD a8aacbd355ca8f4b5aabf9a42c8cb059d2af203b
  branch refs/heads/feat/held
  ```

  With `-z`, every attribute ends in NUL and a record ends in an extra NUL (`...|detached||worktree ...`, NUL shown as `|`). A detached record carries the bare word `detached` and no `branch` line.
- A prunable record, after the worktree directory was moved away: `prunable gitdir file points to non-existent location` follows `detached`.
- `git cherry refs/remotes/origin/main <sha>` accepts a detached commit sha: it printed `+ 0ae5ef71...` for the detached worktree and `+ a8aacbd3...` for `refs/heads/feat/held`.
- The admin dir of a worktree (`.git/worktrees/det/`) holds `HEAD`, `ORIG_HEAD`, `COMMIT_EDITMSG`, `commondir`, `gitdir`, `index`, `logs/`, `refs/`. `git log -g -1 --format='%gd %ct %gs' HEAD` in it printed `HEAD@{0} 1793442113 commit: feat: detached work`, the same second as the `logs/HEAD` mtime.
- Reflog time sources (round 3 fold, scratch repo): a worktree made with `worktree add` under `GIT_COMMITTER_DATE=2026-01-01T00:00:00`, at a commit from earlier in the day, printed `%ct` `1793442113` but selector `HEAD@{1767200400}`, with `logs/HEAD` mtime `1793462227` (now). After `touch -t 202601010000` on the admin `HEAD` and `commondir`, `git reflog expire --all` emptied the reflog (the selector printed nothing) and moved `logs/HEAD` mtime to now (`1793462238`), while the admin `HEAD` and `commondir` stayed at `1767200400`; `gc --auto` left them there too.
- Ignored paths in real worktrees (round 3 fold, read-only, `git -C <wt> --no-optional-locks status --porcelain=v1 --ignored=matching`): `dwarves-kit/.claude/worktrees/move-internal-board` printed `!! .claude/rules/`, `!! .pytest_cache/...` and many `!! .../__pycache__/`; `dwarves-kit/.claude/worktrees/recall-peer-names` printed only `!! .../__pycache__/` entries; `ops-toolkit/.claude/worktrees/bits-fi-console-labs` printed `!! tools/consolelabs-sites-deploy/dist/`. The `.claude/rules/backend-go.md` in the first worktree is byte-identical (`cmp`) to the main checkout's copy, and the main checkout's `.gitignore` ignores `.claude/rules/` (line 21). Every other sampled path is on the regenerable list.
- Index mtime is unusable for idle age: after `touch -t 202601010000` on the admin `index`, `git --no-optional-locks status` left it at `1767200400`, and a plain `git status` moved it to `1793442253`.
- The temporary-index snapshot leaves the worktree untouched: on a worktree with ` M a.txt` and `?? w.txt`, `env GIT_INDEX_FILE=<tmp> git add -A`, `write-tree`, `commit-tree -p HEAD` produced a commit whose `--stat` listed `a.txt | 1 +` and `w.txt | 1 +`. The status string before and after was the same (`[ M a.txt|?? w.txt|]`) and HEAD was unchanged.
- The recomputed snapshot tree is stable with no change (`same tree=yes`) and differs after an in-place edit that keeps the same status code (` M a.txt` both times, `tree changed=yes`). A status comparison alone would miss that edit; AC-15 relies on the tree.
- Create-only lease: `git push origin <sha>:refs/heads/archive/dirty-x --force-with-lease=refs/heads/archive/dirty-x:` printed `* [new branch]` when the ref was absent. With the ref present at the parent of a new commit, the same form printed `! [rejected] ... -> archive/dirty-x (stale info)` and exited 1.
- The fast-forward gap: a plain `git push origin <child>:refs/heads/archive/dirty-x` onto that existing ref printed `473300c..f76acb9` and exited 0; `ls-remote` then showed the ref at the child.
- `git worktree remove` deletes ignored files silently: a clean worktree with ignored `.env` and `node_modules/` (`git status --ignored=matching` printed `!! .env` and `!! node_modules/`) was removed with exit 0 and no output, `.env` included.
- Embedded repository (round 1 fold): a clone made inside the detached sample worktree showed in status as `?? nested/` with `nested/.git` present. A temp-index `add -A` warned `adding embedded git repository: nested`, `ls-tree` on the snapshot tree printed `160000 commit 3fed0c03...	nested`, `diff-tree -r --name-only HEAD <tree>` printed `nested`, and `ls-tree HEAD` held no 160000 entry. So the gitlink scan (snapshot tree minus HEAD tree) and the `diff-tree` name list both see it.
- Depth-2 embedded repository (round 2 fold): with `outer/f.txt` and a clone at `outer/inner/` added to the same worktree, `status --porcelain=v1 -z --untracked-files=normal` printed `?? nested/` and `?? outer/` (no `.git` directly under `outer/`), while `--untracked-files=all` printed `?? nested/`, `?? outer/f.txt` and `?? outer/inner/`. A temp-index `add -A` recorded both gitlinks: `160000 commit 3fed0c03... nested` and `160000 commit 3fed0c03... outer/inner`; HEAD held none.
- The gitlink tree guard is an untested backstop in isolation. Every fixture that makes `add -A` record a new gitlink also shows the nested repo to the `all`-mode status guard as a `??` directory holding `.git`, so deleting the tree guard alone never turns a case red. Its only control is stacked: delete both guards and run AC-30 under `--apply`; the push lands and `-f -f` deletes `nested/`.
- Sampling note: the kit's own hooks blocked a push written with a command substitution and a push inside a script file, the exact failures in `## Problem`. The pushes above ran as plain commands with literal shas against the scratch bare repo.

Dry traces, one per negative control. The code does not exist yet, so each trace reads the order fixed in `## Picture` and TASK-E/F; the build must keep that order or update the trace.

- AC-1 (dry run falls through to the push): the `APPLY != 1` branch after the last guard no longer `continue`s, so control reaches `_wt_snapshot` and the lease push. The fixture's bare origin gains `archive/feat-held-<date>`; `archive_wt_dry_run` asserts the ref is absent with `show-ref --verify` on the bare. Red.
- AC-2 (snapshot before the `APPLY` check): `git add -A` on the temp index writes the untracked file's blob as a loose object. `archive_wt_dry_run_no_objects` compares `git count-objects -v` `count` before and after the dry run; it grows by at least one. Red.
- AC-3 (drop `update-ref -d`): the removal succeeds and `_wt_cleared` passes, but `refs/heads/feat/held` remains. The case asserts `show-ref --verify refs/heads/feat/held` fails. Red.
- AC-4 (detached skip restored): the detached worktree hits `SKIP ... detached HEAD` before the candidate test. No push. The case asserts the bare holds `archive/det-<date>` at the detached sha. Red.
- AC-5 (snapshot from HEAD alone): the archive tip is HEAD, whose tree lacks `w.txt`. `git -C <bare> show archive/feat-dirty-<date>:w.txt` exits non-zero. Red.
- AC-6 (no staleness check): a just-created worktree with one commit passes every other guard (its lock is absent, no process holds it). The push lands; the case asserts no ref on the bare. Red.
- AC-7 (dirty mtimes dropped): with only admin files aged, `_wt_idle_secs` returns about 7 months, so the worktree reads stale and is archived. The case asserts the worktree path still exists. Red.
- AC-8 (live-lock check deleted): the fixture locks the worktree with `pid <background sleep pid>`. The busy check does not fire (the sleep's cwd is elsewhere). The push lands. The case asserts no ref. Red.
- AC-9 (busy check deleted): the fixture starts `(cd <wt> && sleep 300) &`. With no lock, the remove runs under the live process. The case asserts the worktree path exists. Red.
- AC-10 (pre-read deleted, lease replaced by a plain push): the fixture pushed `archive/<slug>-<date>` at `HEAD~1` before the run. With no pre-read, control reaches the push; a plain push fast-forwards the ref to the tip (the sampled gap) and the removal follows. The case asserts the bare ref still equals `HEAD~1`. Red. With only the pre-read deleted, the lease alone refuses with `(stale info)` and the case stays green; AC-11 isolates the lease.
- AC-11 (lease replaced by a plain push): `GIT_TRACE=<file>` makes every git child log its argv as `trace: built-in: git push ...`. The plain push logs no `--force-with-lease=refs/heads/archive/` argument. The case greps the trace for it and fails. Red.
- AC-12 (blockers print nothing): `.env` is ignored, so it is not in the snapshot; the removal with `-f -f` deletes it (sampled). The case asserts `<wt>/.env` exists. Red.
- AC-13 (`node_modules` dropped from the list): `_wt_ignored_blockers` prints `node_modules`, so the case sees `SKIP` and no `archived worktree` line. Red.
- AC-14 (secret check deleted): `.env.local` is untracked and not ignored, so `git add -A` takes it into the snapshot. The case asserts `git -C <bare> show <ref>:.env.local` fails; it succeeds. Red.
- AC-15 (post-push recompute deleted): the pre-push hook appends a line to `a.txt` in the worktree. Without the recompute, the remove runs and the appended line exists nowhere. The case asserts the worktree path exists and `a.txt` holds the line. Red.
- AC-16 (both guards between push and removal removed): the pre-push hook exits 1 and the push fails. With the failure branch gone, control falls to the read-back; with the read-back gone too, the remove runs. The case asserts the worktree path exists. Red. Either guard alone keeps the case green, which is the intended depth.
- AC-17 (merge proof deleted): a plain ancestor has no `+` in `git cherry` and would never reach the proof check, so the fixture squashes the branch's two commits into one commit on origin/main. The patch ids differ, so `git cherry` prints `+` twice, while `_absorbed` holds (every changed path is byte-identical on origin/main). Without the proof check, the worktree is archived. The case asserts no ref on the bare. Red.
- AC-18 (cherry test inverted): the detached worktree at origin/main reads as a candidate and is archived. The case asserts no ref and the path still exists. Red.
- AC-19 (`--own` skip deleted): the loop runs and prints `WOULD archive worktree` for the stale fixture. The case asserts that text is absent. Red.
- AC-20 (conflict check deleted): `cmd_apply` accepts the pair; `--pull-only` skips the sweep and exits 0. The case asserts exit 64. Red.
- AC-21 (unconditional call): `-- archive worktrees:` prints with the flag off. The case asserts the text is absent. Red.
- AC-22 (project-aware knob read): `kit_config_get` reads the project `.kit.toml` value `1`, so the worktree aged to 2026-01-01 is stale and archived despite the root value. The case asserts no ref. Red.
- AC-23 (protected check deleted): the `master` worktree carries one commit origin/main lacks, so `git cherry` prints `+`, it is stale, and `WOULD archive` prints. The case asserts that text is absent. Red.
- AC-24 (submodule check deleted): the fixture adds a local submodule and runs `submodule update --init` in the worktree. The sweep archives and `-f -f` removes the initialized submodule. The case asserts the worktree path exists. Red.
- AC-25 (prunable check deleted): the record's `prunable` attribute is ignored, `cd <moved path>` fails, and the unresolvable line prints. The case asserts the exact `prunable` text. Red.
- AC-30 (status guard deleted alone): the `?? nested/` entry passes every other guard, so the dry run reaches the `WOULD archive worktree` line. The case asserts the dry run prints `SKIP ... embedded git repository (nested)` and no `WOULD` line. Red. Under `--apply` the tree guard still catches the new gitlink, which is why the red verdict is read from the dry run. The stacked control (both guards deleted, `--apply`) is the tree guard's only control: the push lands a tree whose `nested` gitlink points at a commit origin may lack, `-f -f` deletes `nested/`, and the case's `nested/.git` assertion fails. Red.
- AC-30b (`--untracked-files=normal`): status prints `?? outer/` (sampled); `outer/.git` does not exist, so the guard passes it and the dry run prints `WOULD archive worktree`. The case asserts the SKIP line naming `outer/inner/`. Red.
- AC-31 (staged-tree check dropped, status check limited to `??`): `.env` is `A ` in status, so the limited status check passes it; `_wt_snapshot` builds the staged commit holding `.env`; only the snapshot-tree `diff-tree` remains, and `add -A` on the temp index keeps the already-staged `.env` (ignore rules do not drop a tracked index entry), so that check also names it. To make the control bite, the mutation drops both `diff-tree` checks along with the status narrowing. The push lands and `git -C <bare> show <ref>~1:.env` succeeds. The case asserts it fails. Red.
- AC-32 (old land pattern): `id_rsa` matches none of `.env* *.pem *.key *secret* *credential* *token*`, so every secret check passes it, `add -A` takes it, and the push lands. The case asserts `git -C <bare> show <ref>:id_rsa` fails. Red.
- AC-33 (invoking-worktree guard deleted): the test runs wrap with `cd <wt> &&`. `_wt_busy` exempts wrap's own pid and ancestors, so it does not fire; every other guard passes on the aged fixture; the push lands and the remove runs. The case asserts the worktree path exists. Red.
- AC-34 (admin part read from the `logs/HEAD` mtime): after `reflog expire --all` that mtime is now, so idle age is 0 and the case sees `SKIP ... fresh`. It asserts `WOULD archive worktree`. Red.
- AC-35 (guard deleted): the `UU` fixture reaches `_wt_snapshot`; `write-tree` on the copied index refuses unmerged entries, so the line is `FAILED ... snapshot failed` and `apply` exits 2. The case asserts the SKIP line and exit 0. Red. The unborn fixture fails the same way at `commit-tree -p HEAD`.
- AC-36 (section skip deleted): with `KIT_WRAP_SKIP_BUSY_CHECK=1`, `_wt_busy` returns "not busy" (`wrap-apply.sh:124`), every other guard passes on the aged fixture, and the push lands. The case asserts no ref on the bare. Red.
- AC-37 (class widened to any `.claude/` path): in fixture (b), `.claude/rules/x.md` differs from the main checkout's copy, so the real class blocks it. Widened, `_wt_ignored_blockers` prints nothing, the push lands, and `-f -f` deletes the file. The case asserts the SKIP line and that the file still exists. Red.
- AC-29 (in-progress check deleted): the fixture starts a rebase that stops on a conflict-free `edit` step, so the worktree is detached with admin `rebase-merge/` present and a commit origin lacks. Without the check it is a candidate and is archived mid-rebase. The case asserts no ref on the bare. Red.
- AC-26 (sed range unchanged): `_usage` prints lines 2 to 42; the new header lines sit past 42. The case greps `--help` output for `--archive-worktrees`. Red.
- AC-27 (bullet removed): the case greps `commands/wrap.md` for `--archive-worktrees`; zero hits. Red.

## Open questions
(none)
