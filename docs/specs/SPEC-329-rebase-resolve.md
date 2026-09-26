# SPEC-329: wrap rebase moves a worktree branch onto origin/<default> and resolves only the safe conflicts

**Status:** DRAFT (awaiting fresh-context validation)
Lane: full
Type: spec-feature
**Proof:** `docs/verification/rebase-resolve.md`; `tests/test-wrap.sh`, the rebase block.

## Problem

In one session the lead rebased a worktree branch onto `origin/<default>` four times by hand. Each time it ran the same loop: at every rebase stop, keep both sides of `docs/CHANGELOG.md`, regenerate `docs/FEATURES.md` with `lib/registry/feature-registry.sh generate`, stop on anything else, check for leftover conflict markers, `git rebase --continue`, then regenerate once more at the end. One chained variant (`git add -A && git rebase --continue`) committed conflict markers into a pick.

Two facts from the repo shape the fix:

- `docs/CHANGELOG.md` is NOT declared `merge=union`. `git check-attr merge -- docs/CHANGELOG.md` prints `unspecified`. `.gitattributes` declares `_meta/BACKLOG.md`, `_meta/backlog-staging.md` and `docs/implementation-notes/*.md` only. That is why the lead resolved CHANGELOG by hand.
- git applies a declared `merge=union` attribute during a rebase, as it does during the `git merge` that `wrap merge`'s re-merge runs. A scratch repo on git 2.55 confirmed it: a union-declared file that both sides appended to never stopped the rebase, even when the branch's own earlier pick added the declaration.

## Contract

`bin/wrap rebase <worktree>`

- `<worktree>` is any checkout of the repo (a `.claude/worktrees/<slug>` worktree or the main checkout). The verb refuses, exit 1, with one line naming the reason, when:
  - the path is not a git work tree, or HEAD is detached;
  - the branch is the detected default branch, `main` or `master`;
  - a rebase, merge or cherry-pick is already in progress there;
  - a tracked file is modified or staged (untracked files are allowed);
  - an `index.lock` is held by another writer (`_write_guard`);
  - `git fetch origin <default>` fails, or no default branch resolves.
- A missing argument, an extra argument or an unknown flag exits 64 with a usage line.
- When `origin/<default>` is already an ancestor of HEAD, the verb prints `nothing to rebase: <branch> already contains origin/<default>` and exits 0 with no write.
- Otherwise it runs `git rebase origin/<default>` non-interactively (`GIT_EDITOR=true`). At each stop it lists the unmerged paths and classifies each one:

| Class | Rule | Action at the stop |
|---|---|---|
| generated | the path is `docs/FEATURES.md` AND `<worktree>/lib/registry/feature-registry.sh` exists | run that generator, from the worktree, once per stop |
| union-declared | `git check-attr merge` reads `union` | none of its own: git already resolved every content conflict on it, so a path still unmerged here is a delete or rename conflict. Refused, named with `(merge=union, delete/rename conflict)` |
| anything else | | refused |

- One refused path aborts the whole run: `git rebase --abort`, then the verb prints `REFUSED <branch>: conflict in <path>, <path>`, confirms HEAD is back at the pre-rebase tip, and exits 1.
- After the generator runs, the verb scans every path it is about to stage (the unmerged paths plus every tracked file the generator changed) for a conflict-marker line, `^(<<<<<<<|>>>>>>>|\|\|\|\|\|\|\|)( |$)`. A hit aborts the rebase the same way and prints `MARKERS <branch>: <path>, <path>`, exit 1. The scan runs before `git add`, so a marker can never reach a pick.
- The verb stages with `git add -- <paths>` for the unmerged paths and `git add -u` for the generator's side effects (it also syncs count strings in `README.md` and `docs/architecture.md`), then runs `git rebase --continue`. A pick that becomes empty after the regeneration is dropped by git itself (git 2.55 `--continue` does this silently).
- A generator that exits non-zero at a stop aborts the rebase and exits 1 with `GENERATOR FAILED <branch>`.
- A stop with no unmerged path (a pick that failed on an untracked file it would overwrite, for example) aborts and exits 1 with the first line of git's message.
- The loop is bounded: at most one stop per commit in `origin/<default>..HEAD`, plus one. Past the bound it aborts and exits 1.
- The verb runs `git commit` only once the rebase is finished (no `rebase-merge` or `rebase-apply` directory under the worktree's git dir). While a rebase is stopped it never commits.
- After the rebase completes, when the generator exists, the verb runs it once more. When that changes tracked files, it scans them for markers (same rule, a hit leaves them unstaged and exits 1), stages them with `git add -u` and commits `chore(registry): regenerate FEATURES.md after rebase`. A failed commit leaves the changes staged and exits 1.
- Success prints `rebased <branch> onto origin/<default>: <n> stop(s) resolved, head <sha7> (was <sha7>)` and one `not pushed: ...` line saying the history changed and the push needs `--force-with-lease`. Exit 0.
- The verb never pushes, never switches a branch, never runs `reset`, and touches no checkout but `<worktree>`.

Repo change in the same PR: `.gitattributes` adds `docs/CHANGELOG.md merge=union`, with one comment line naming the trade (below). With that line, git keeps both sides of a CHANGELOG collision in this verb, in `wrap merge`'s re-merge, and in any hand merge.

## Picture

```
 lead / /kit:wrap step 10 worker
          |
          v
 bin/wrap rebase <worktree>
          |
          v
 lib/wrap/wrap.sh cmd_rebase
   preflight (branch, clean, no op in progress, lock) --fail--> exit 1
          |
          v
   git fetch origin <def> ----> already contains? --> exit 0 "nothing to rebase"
          |
          v
   git rebase origin/<def>          (git's own union driver resolves
          |                           every merge=union content conflict)
          v
   +-------------- stop loop ----------------+
   | unmerged paths                          |
   |   generated -> <wt>/lib/registry/       |
   |                feature-registry.sh      |
   |                generate                 |
   |   other     -> rebase --abort, exit 1   |
   | marker scan -> hit: --abort, exit 1     |
   | git add; rebase --continue              |
   +-----------------------------------------+
          |
          v
   rebase done --> generate again --> changed? --> scan, add -u, one commit
          |
          v
   exit 0 (not pushed)
```

## Design

Design-bearing: a new verb that rewrites a local branch through a bounded loop over rebase stops.

State of one run:

```
                 +-----------+  fetch ok, behind   +-----------+
   start ------> | PREFLIGHT | ------------------> | REBASING  |
                 +-----------+                     +-----------+
                   |      |                          |       |
          refused  |      | already contains         | stop  | finished
          exit 1 <-+      +--> exit 0                v       v
                                               +---------+  +-----------+
                                               | STOPPED |  | FINISHED  |
                                               +---------+  +-----------+
                                                 |  |  |      |   regenerate;
                            only generated paths |  |  |      |   changed -> scan,
                            + generator ok       |  |  |      |   add -u, commit
                            + no markers         |  |  |      v
                            add; --continue -----+  |  |    exit 0 (or 1 on
                            (back to REBASING)      |  |    marker / commit fail)
                                                    |  |
                refused path / markers / gen fail --+  +-- no unmerged path, or
                                                    |      stop bound exceeded
                                                    v
                                              +---------+
                                              | ABORTED | git rebase --abort,
                                              +---------+ HEAD == pre-rebase tip,
                                                          exit 1
```

The one commit edge leaves FINISHED, never STOPPED.

Approaches considered:

| Approach | Why not |
|---|---|
| Resolve union files inside the verb (`git merge-file --union` over stages 1 to 3 at each stop) | git's union driver already resolves them during the rebase. A union path still unmerged at a stop is a delete or rename conflict, which "keep both sides" cannot express. The branch would be unreachable code. `wrap merge`'s `_remerge_push` relies on the same fact and treats a stop as a real conflict. |
| Hardcode CHANGELOG as union inside the verb | A second source of truth next to `.gitattributes`, and `wrap merge` would still conflict on CHANGELOG. One `.gitattributes` line fixes both. |
| `git merge origin/<def>` instead of a rebase | The lead's loop rebases so the PR stays linear; a merge commit changes what the squash sees. `wrap merge` already owns the merge shape. |
| A declared generated-file list (`[wrap] rebase_generated` knob or a custom gitattribute) | One generated file exists. A gitattribute cannot carry a command with spaces, and a knob is config for a single pair. The rule below is the smallest honest one; the knob is the upgrade path when a second generated file appears. |
| `git add -A` then `--continue` | This is the chained variant that committed markers. It also stages untracked files. The verb stages named paths plus `git add -u`, after the marker scan. |
| `git rebase --skip` for a pick left empty | git 2.55 `--continue` drops a pick left empty by the resolution on its own. A `--skip` would also drop a non-empty pick if mis-detected. |

Generated-file rule, stated: a path is generated when it is `docs/FEATURES.md` and the worktree carries `lib/registry/feature-registry.sh`. The generator runs from the worktree being rebased, never from the installed kit (`$LIB_ROOT`), because the projection must match the tree under rebase. In a consumer repo without that generator, `docs/FEATURES.md` is an ordinary file and a conflict on it is refused.

Marker rule, stated: the scan covers the paths the verb stages. Paths git merged cleanly are git's output and carry no new markers. The pattern needs the marker plus a space or line end, so seven `=` signs alone (a Markdown heading underline) never trip it; every conflict hunk carries both a `<<<<<<<` and a `>>>>>>>` line, so the two outer markers are enough.

## Failure modes

| Class | Detection | Mitigation |
|---|---|---|
| Real conflict in a hand-written file (a shared command doc, a test) | unmerged path outside the generated rule | abort, name every refused path, HEAD back at the old tip, exit 1 |
| Generator leaves the marked file as it was (no-op, crash after partial write) | marker scan before `git add` | abort, `MARKERS`, exit 1; nothing staged |
| Generator exits non-zero mid-rebase | exit code | abort, `GENERATOR FAILED`, exit 1 |
| Generator changes README.md count strings at a stop | `git add -u` stages them; markers scanned first | the pick carries counts that match its tree; the final pass syncs again |
| Union file collision where one side edited a bullet in place | none (git resolves it) | union keeps both versions of the line. Accepted trade, named in the `.gitattributes` comment; review the CHANGELOG diff before merge |
| Delete or rename conflict on a union-declared file | unmerged path that check-attr reads union | refused with the union note, exit 1 |
| Pick blocked by an untracked file it would overwrite | stop with zero unmerged paths | abort, first line of git's message, exit 1 |
| `--continue` keeps returning the same stop | stop count past commits + 1 | abort, exit 1 |
| `git rebase --abort` itself fails | HEAD != pre-rebase tip after abort | print `ABORT FAILED ... run git rebase --abort in <wt>`, exit 1 |
| Branch already pushed | always, on success | `not pushed` line names `--force-with-lease`; the verb never pushes |
| Stale default ref | `git fetch origin <def>` before the rebase | fetch failure refuses |
| Another writer mid-operation | `_write_guard`, in-progress checks | refused before any write |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: the verb | `lib/wrap/wrap.sh` (`cmd_rebase` and helpers, header verb list, write-set paragraph, `main` dispatch), `bin/wrap` help | the Contract above; `wrap --help` names `rebase` |
| T2: union declaration | `.gitattributes` | `git check-attr merge -- docs/CHANGELOG.md` reads `union`; the comment names the edited-bullet trade |
| T3: tests | `tests/test-wrap.sh` | every Test plan row passes in scratch repos with a bare origin and a stub generator |
| T4: docs | `docs/CHANGELOG.md`, `commands/wrap.md` and `docs/consumer-contract.md` where they list the verbs | the verb and its exit codes are named once |

## Test plan

All cases build a scratch repo with a bare `origin`, a default branch, and a feature worktree. The generator is a stub at `lib/registry/feature-registry.sh` that writes `docs/FEATURES.md` from a sorted file listing, so a regeneration is deterministic.

| Case | Setup | Expected |
|---|---|---|
| Nothing to rebase | branch already contains origin/<def> | exit 0, `nothing to rebase`, HEAD unchanged |
| Clean rebase | disjoint changes | exit 0, `0 stop(s) resolved`, origin/<def> is an ancestor of HEAD |
| Union handled by git | both sides append to a union-declared file | exit 0, both lines present, `0 stop(s)` |
| CHANGELOG declared | `git check-attr merge -- docs/CHANGELOG.md` in the kit repo | `union` |
| Generated stop | both sides change `docs/FEATURES.md` and add a listed file | exit 0, `1 stop(s) resolved`, FEATURES equals a fresh generate, no marker anywhere in `git log -p origin/<def>..HEAD` |
| Empty pick after regen | the branch's only change to a pick is FEATURES | exit 0, that pick is gone, no empty commit |
| Final regeneration | origin adds a listed file with no FEATURES change, the branch's FEATURES is stale | exit 0, last commit is `chore(registry): regenerate FEATURES.md after rebase` and its tree's FEATURES equals a fresh generate |
| No final commit when fresh | final generate changes nothing | exit 0, no regen commit |
| Refused conflict | both sides edit the same line of `other.md` | exit 1, `REFUSED` names `other.md`, HEAD equals the old tip, no rebase in progress |
| Mixed stop | one stop has FEATURES and `other.md` unmerged | exit 1, names `other.md` only, nothing resolved or staged, old tip restored |
| Leftover markers (negative control target) | stub generator is a no-op, so git's markers stay in FEATURES | exit 1, `MARKERS` names `docs/FEATURES.md`, old tip restored, no marker in any commit |
| Generator fails | stub exits 3 | exit 1, `GENERATOR FAILED`, old tip restored |
| No generator (consumer repo) | FEATURES conflicts, no `lib/registry/feature-registry.sh` | exit 1, refused by name |
| Union delete conflict | origin deletes a union-declared file the branch edits | exit 1, refused with the union note |
| No commit while stopped | generated stop, commit count checked | `git rev-list --count origin/<def>..HEAD` equals the surviving picks plus at most the one regen commit; no commit has two parents |
| Preflight refusals | default branch, detached HEAD, dirty tracked file, rebase already in progress, not a repo | exit 1, one reason line, nothing changed |
| Usage | no argument, two arguments, unknown flag | exit 64 |
| Help | `wrap --help` and `bin/wrap` header | both name `rebase` |

Negative control: `lib/gate/negctl.sh` mutates the marker scan so it reports no markers. The Leftover markers case must go red.

## Verification

`bash tests/test-wrap.sh` exits 0. `bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" "<marker scan returns clean>"` reports PASS. `bash tests/run-all.sh --changed` exits 0.

## After state

A worktree branch that fell behind moves onto `origin/<default>` with one command: `bin/wrap rebase <worktree>`. Generated FEATURES conflicts resolve by regeneration, union files resolve through git's own driver (CHANGELOG now included), every other conflict aborts cleanly by name, and no conflict marker can reach a commit. The operator pushes with `--force-with-lease`.

Not covered: kanban rows duplicated by a union merge are not deduped here (`wrap merge` runs `backlog.sh dedupe-all` after its re-merge; after this verb the next `board set` refuses loudly, as `.gitattributes` already documents). A second generated file needs the knob named in the Design. The verb does not push.

## Decision Log

- CHANGELOG goes into `.gitattributes` instead of a verb-local rule: one source of truth, and `wrap merge`'s re-merge gains it for free. Cost: an edited bullet next to an added bullet comes out twice instead of stopping.
- No verb-local union resolver: git resolves declared union files during a rebase (checked on git 2.55, including a declaration added by an earlier pick of the same branch).
- Generated rule is one hardcoded pair gated on the generator's presence, with a `ponytail:` comment naming the knob as the upgrade path.
- The final regeneration commits, because a FEATURES left stale after the rebase fails `tests/test-meta.sh` and the pre-push ship-gate.
- No dry-run: the only write is the local branch rewrite, recoverable from the printed old tip or the reflog.
