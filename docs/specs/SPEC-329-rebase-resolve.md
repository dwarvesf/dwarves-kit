# SPEC-329: wrap rebase moves a worktree branch onto origin/<default> and resolves only the safe conflicts

**Status:** VALIDATED
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

- A missing argument, an extra argument or an unknown flag exits 64 with a usage line. A path that is not a git work tree, or does not resolve, exits 64, the same as `wrap land`.
- The verb refuses, exit 1, with one line naming the reason, when:
  - the path is the main checkout (the git common dir's parent), the same refusal `wrap land` makes;
  - HEAD is detached;
  - the branch is the detected default branch, `main` or `master`, or no default branch resolves;
  - a rebase, merge or cherry-pick is already in progress there;
  - a tracked file is modified or staged (untracked files are allowed);
  - an `index.lock` is held by another writer (`_write_guard`);
  - `git fetch origin <default>` fails.
- When `origin/<default>` is already an ancestor of HEAD, the verb prints `nothing to rebase: <branch> already contains origin/<default>` and exits 0 with no write.
- Otherwise it runs `git -c rerere.enabled=false -c rebase.updateRefs=false rebase origin/<default>` non-interactively (`GIT_EDITOR=true`). Every `--continue` carries the same two `-c` pins, so a recorded rerere resolution or an operator's `updateRefs` default can never act inside the verb. At each stop it lists the unmerged paths and classifies each one:

| Class | Rule | Action at the stop |
|---|---|---|
| generated | the path is `docs/FEATURES.md` AND `<worktree>/lib/registry/feature-registry.sh` exists | run that generator, from the worktree, once per stop |
| changelog | the path is `docs/CHANGELOG.md`, all three stages (`:1:` base, `:2:`, `:3:`) exist, and neither side deletes or changes a base line (a plain `diff` of base against each side prints no `<` line) | `git merge-file --union -p` over the three stages, written to the path: both sides' additions kept |
| anything else | includes a CHANGELOG conflict that fails the pure-addition test, and a union-declared path (git's union driver already resolved every content conflict on those, so one still unmerged is a delete or rename conflict, named with `(merge=union, delete/rename conflict)`) | refused |

- One refused path aborts the whole run: `git rebase --abort`, then the verb prints `REFUSED <branch>: conflict in <path>, <path>`, confirms HEAD is back at the pre-rebase tip, and exits 1. Classification of every path runs before any resolution, so a refused stop writes nothing.
- The stage set is exact. Before the resolver and the generator run, the verb records `git diff --name-only`; after, it records it again. The set is the unmerged paths plus every path that appears only in the after list (the generator also syncs count strings in `README.md` and `docs/architecture.md`). The verb scans each path in that set for a conflict-marker line, `^(<<<<<<<|>>>>>>>|\|\|\|\|\|\|\|)( |$)`. A hit aborts the rebase the same way and prints `MARKERS <branch>: <path>, <path>`, exit 1. Only then does it run `git add -- <that set>`. Never `git add -u`, never `git add -A`.
- Then `git rebase --continue`. A pick that becomes empty after the resolution is dropped by git itself (git 2.55 `--continue` does this silently).
- A generator that exits non-zero at a stop aborts the rebase and exits 1 with `GENERATOR FAILED <branch>`.
- A stop with no unmerged path (a pick that failed on an untracked file it would overwrite, for example) aborts and exits 1 with the first line of git's message.
- The loop is bounded: at most one stop per commit in `origin/<default>..HEAD`, plus one. Past the bound it aborts and exits 1 with `STOP BOUND`. The internal test seam `WRAP_REBASE_MAX_STOPS` overrides the bound.
- When `git rebase --abort` fails or leaves HEAD off the pre-rebase tip, the verb prints `ABORT FAILED <branch>: run git rebase --abort in <worktree>` and exits 1.
- The verb runs `git commit` only once the rebase is finished (no `rebase-merge` or `rebase-apply` directory under the worktree's git dir). While a rebase is stopped it never commits.
- After the rebase completes, when the generator exists, the verb runs it once more with the same before/after `git diff --name-only` record. When the after list names paths, it scans them for markers (a hit leaves them unstaged, prints `MARKERS`, exits 1), stages exactly them with `git add --`, and commits `chore(registry): regenerate FEATURES.md after rebase`. A failed commit leaves the changes staged and exits 1.
- Success prints `rebased <branch> onto origin/<default>: <n> stop(s) resolved, head <sha7> (was <sha7>)` and one `not pushed: ...` line saying the history changed and the push needs `--force-with-lease`. Exit 0.
- The verb never pushes, never switches a branch, never runs `reset`, and touches no checkout but `<worktree>`.
- `commands/wrap.md` step 10 runs `bin/wrap rebase <wt>` before it pushes a built branch; a refusal keeps the item `REPORTED` with the refusal line as its why.

## Picture

```
 /kit:wrap step 10 (before the push)      a lead by hand
                 \                          /
                  v                        v
               bin/wrap rebase <worktree>
                          |
                          v
 lib/wrap/wrap.sh cmd_rebase
   preflight (worktree not main, branch, clean,
              no op in progress, lock) -----------fail--> exit 64 / 1
          |
          v
   git fetch origin <def> ----> already contains? --> exit 0 "nothing to rebase"
          |
          v
   git rebase origin/<def>          (git's own union driver resolves
          |                           every merge=union content conflict)
          v
   +-------------- stop loop ------------------+
   | unmerged paths, classified first          |
   |   generated -> <wt>/lib/registry/         |
   |                feature-registry.sh        |
   |                generate                   |
   |   changelog, pure additions both sides    |
   |             -> git merge-file --union     |
   |   other     -> rebase --abort, exit 1     |
   | stage set = unmerged + new diff paths     |
   | marker scan -> hit: --abort, exit 1       |
   | git add -- <set>; rebase --continue       |
   +-------------------------------------------+
          |
          v
   rebase done --> generate again --> new paths? --> scan, add --, one commit
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
     exit 64/1 <---+      +--> exit 0                v       v
                                               +---------+  +-----------+
                                               | STOPPED |  | FINISHED  |
                                               +---------+  +-----------+
                                                 |  |  |      |   regenerate;
             only generated / pure-add CHANGELOG |  |  |      |   new paths -> scan,
             paths + generator ok + no markers   |  |  |      |   add --, commit
             add -- <set>; --continue -----------+  |  |      v
             (back to REBASING)                     |  |    exit 0 (or 1 on
                                                    |  |    marker / commit fail)
             refused path / markers / gen fail -----+  +-- no unmerged path, or
                                                    |      stop bound exceeded
                                                    v
                                              +---------+  git rebase --abort;
                                              | ABORTED |  HEAD == pre-rebase tip,
                                              +---------+  exit 1 (ABORT FAILED if not)
```

The one commit edge leaves FINISHED, never STOPPED.

Approaches considered:

| Approach | Why not |
|---|---|
| Declare `docs/CHANGELOG.md merge=union` in `.gitattributes` | It silently changes `wrap apply` (`_pull_default`, `_carry_stray`, `_carry_stray_commits`), `wrap land` (`_land_ff_pull`) and `wrap merge` (`_union_remerge` would merge CHANGELOG edits nobody reviewed). It also breaks the rule in `.gitattributes` itself: a file whose lines are rewritten in place stays off the union list. A probe showed a reworded bullet kept twice with no stop. |
| Union every CHANGELOG conflict inside the verb | Same duplicate-bullet failure, only scoped to rebase. The pure-addition test keeps the safe case (two branches each adding bullets) and refuses the rest. |
| Resolve union-declared files inside the verb (`git merge-file --union` at each stop) | git's union driver already resolves them during the rebase. One still unmerged at a stop is a delete or rename conflict, which "keep both sides" cannot express. `wrap merge`'s `_remerge_push` relies on the same fact. |
| `git merge origin/<def>` instead of a rebase | The lead's loop rebases so the PR stays linear. `wrap merge` already owns the merge shape. |
| A declared generated-file list (`[wrap] rebase_generated` knob or a custom gitattribute) | One generated file exists. A gitattribute cannot carry a command with spaces, and a knob is config for a single pair. The rule below is the smallest honest one; the knob is the upgrade path when a second generated file appears. |
| `git add -A` or `git add -u` then `--continue` | `add -A` is the chained variant that committed markers. `add -u` stages whatever tracked file changed, scanned or not. The verb stages an explicit set after the marker scan. |
| `git rebase --skip` for a pick left empty | git 2.55 `--continue` drops a pick left empty by the resolution on its own. A `--skip` would drop a non-empty pick if mis-detected. |

Generated-file rule: a path is generated when it is `docs/FEATURES.md` and the worktree carries `lib/registry/feature-registry.sh`. The generator runs from the worktree being rebased, never from the installed kit (`$LIB_ROOT`), because the projection must match the tree under rebase. In a consumer repo without that generator, `docs/FEATURES.md` is an ordinary file and a conflict on it is refused.

CHANGELOG rule: a pure addition is a side whose `diff` against the base prints only `>` lines. Both sides pure means both only inserted bullets; `git merge-file --union` then keeps both insertions and drops no base line. A side that rewords, moves or deletes a base line fails the test, and the verb refuses by name. The path is the kit's own `docs/CHANGELOG.md`; a consumer with a CHANGELOG elsewhere gets the plain refusal.

Marker rule: the scan covers exactly the stage set. Paths git merged cleanly are git's output and carry no new markers. The pattern needs the marker plus a space or line end, so seven `=` signs alone (a Markdown heading underline) never trip it; every conflict hunk carries both a `<<<<<<<` and a `>>>>>>>` line, so the two outer markers are enough.

## Failure modes

| Class | Detection | Mitigation |
|---|---|---|
| Real conflict in a hand-written file (a shared command doc, a test) | unmerged path outside the handled classes | abort, name every refused path, HEAD back at the old tip, exit 1 |
| CHANGELOG bullet reworded on one side | base line missing from that side's stage | refused by name; the operator resolves it |
| CHANGELOG added on both sides (add/add, no base stage) | stage `:1:` missing | refused by name |
| Generator leaves the marked file as it was (no-op, crash after partial write) | marker scan before `git add` | abort, `MARKERS`, exit 1; nothing staged |
| Generator exits non-zero mid-rebase | exit code | abort, `GENERATOR FAILED`, exit 1 |
| Generator changes README.md count strings at a stop | before/after `git diff --name-only` record | staged by name after the scan; the final pass syncs again |
| Delete or rename conflict on a union-declared file | unmerged path that check-attr reads union | refused with the union note, exit 1 |
| rerere replays an old wrong resolution | none needed | `-c rerere.enabled=false` on every rebase call |
| Operator config `rebase.updateRefs=true` moves stacked branches | none needed | `-c rebase.updateRefs=false` on every rebase call |
| Pick blocked by an untracked file it would overwrite | stop with zero unmerged paths | abort, first line of git's message, exit 1 |
| `--continue` keeps returning a stop | stop count past commits + 1 | abort, `STOP BOUND`, exit 1 |
| `git rebase --abort` itself fails | exit code, HEAD != pre-rebase tip | `ABORT FAILED ... run git rebase --abort in <wt>`, exit 1 |
| Verb pointed at the main checkout | common dir parent equals the path | refused before any write, exit 1 |
| Branch already pushed | always, on success | `not pushed` line names `--force-with-lease`; the verb never pushes |
| Stale default ref | `git fetch origin <def>` before the rebase | fetch failure refuses |
| Another writer mid-operation | `_write_guard`, in-progress checks | refused before any write |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1a: preflight and no-op | `lib/wrap/wrap.sh` (`cmd_rebase` argument parse and preflight, `main` dispatch, header verb list, write-set paragraph), `bin/wrap` help | usage 64, non-worktree 64, every preflight refusal 1, `nothing to rebase` 0; `wrap --help` names `rebase` |
| T1b: the stop loop | `lib/wrap/wrap.sh` (classify, CHANGELOG resolver, generator run, exact stage set, marker scan, abort, bound) | the Contract's stop rules |
| T1c: final regeneration | `lib/wrap/wrap.sh` | the post-rebase generate, scan and single commit |
| T2: tests | `tests/test-wrap.sh` | every Test plan row passes in scratch repos with a bare origin and a stub generator |
| T3: docs | `docs/CHANGELOG.md`, `commands/wrap.md` step 10 (one sentence before the push), `docs/consumer-contract.md` `bin/wrap` row | the verb and its exit codes are named once; step 10 calls it |

## Test plan

All cases build a scratch repo with a bare `origin`, a default branch, and a feature worktree made with `git worktree add`. The generator is a stub at `lib/registry/feature-registry.sh` that writes `docs/FEATURES.md` from a sorted file listing, so a regeneration is deterministic.

| Case | Setup | Expected |
|---|---|---|
| Nothing to rebase | branch already contains origin/<def> | exit 0, `nothing to rebase`, HEAD unchanged |
| Clean rebase | disjoint changes | exit 0, `0 stop(s) resolved`, origin/<def> is an ancestor of HEAD |
| Union handled by git | both sides append to a union-declared file | exit 0, both lines present, `0 stop(s)` |
| CHANGELOG pure additions | both sides insert a different bullet at the same point | exit 0, both bullets present once, every base line kept, `1 stop(s)` |
| CHANGELOG reworded | origin rewords a base bullet, the branch inserts next to it | exit 1, `REFUSED` names `docs/CHANGELOG.md`, old tip restored |
| Generated stop | both sides change `docs/FEATURES.md` and add a listed file | exit 0, `1 stop(s) resolved`, FEATURES equals a fresh generate, no marker anywhere in `git log -p origin/<def>..HEAD` |
| Generator side effect staged | stub also rewrites a tracked `README.md` count at the stop | exit 0, the README change is in the pick, worktree clean |
| Empty pick after regen | the branch's only change to a pick is FEATURES | exit 0, that pick is gone, no empty commit |
| Final regeneration | origin adds a listed file with no FEATURES change, the branch's FEATURES is stale | exit 0, last commit is `chore(registry): regenerate FEATURES.md after rebase` and its FEATURES equals a fresh generate |
| No final commit when fresh | final generate changes nothing | exit 0, no regen commit |
| Refused conflict | both sides edit the same line of `other.md` | exit 1, `REFUSED` names `other.md`, HEAD equals the old tip, no rebase in progress |
| Mixed stop | one stop has FEATURES and `other.md` unmerged | exit 1, names `other.md` only, FEATURES not regenerated, old tip restored |
| Leftover markers (negative control target) | stub generator is a no-op, so git's markers stay in FEATURES | exit 1, `MARKERS` names `docs/FEATURES.md`, old tip restored, no marker in any commit |
| Generator fails | stub exits 3 | exit 1, `GENERATOR FAILED`, old tip restored |
| No generator (consumer repo) | FEATURES conflicts, no `lib/registry/feature-registry.sh` | exit 1, refused by name |
| Union delete conflict | origin deletes a union-declared file the branch edits | exit 1, refused with the union note |
| Stop bound | `WRAP_REBASE_MAX_STOPS=0`, a generated stop | exit 1, `STOP BOUND`, old tip restored |
| Abort fails | a `git` shim first on PATH fails `rebase --abort`, refused conflict | exit 1, `ABORT FAILED` names the worktree |
| No commit while stopped | generated stop | no commit in `origin/<def>..HEAD` has two parents; the count equals the surviving picks plus at most one regen commit |
| Preflight refusals | main checkout, default branch, detached HEAD, dirty tracked file, rebase already in progress, stale `index.lock`, fetch failure | exit 1, one reason line, HEAD unchanged |
| Usage | no argument, two arguments, unknown flag, not a repo | exit 64 |
| Help | `wrap --help` and `bin/wrap` header | both name `rebase` |

Negative control: `lib/gate/negctl.sh` mutates the marker scan so it reports no markers. The Leftover markers case must go red.

## Verification

`bash tests/test-wrap.sh` exits 0. `bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" "<marker scan returns clean>"` reports PASS. `bash tests/run-all.sh --changed` exits 0.

## After state

A worktree branch that fell behind moves onto `origin/<default>` with one command: `bin/wrap rebase <worktree>`, and `/kit:wrap` step 10 runs it before each push. Generated FEATURES conflicts resolve by regeneration, CHANGELOG conflicts where both sides only added lines keep both, union-declared files resolve through git's own driver, every other conflict aborts cleanly by name, and no conflict marker can reach a commit. The operator pushes with `--force-with-lease`.

Not covered: kanban rows duplicated by a union merge are not deduped here (`wrap merge` runs `backlog.sh dedupe-all` after its re-merge; after this verb the next `board set` refuses loudly, as `.gitattributes` already documents). A second generated file needs the knob named in the Design. The verb does not push.

## Decision Log

- Validation (fresh context): APPROVED, 0 critical, design record pass, 8 warnings. The lead replaced the `.gitattributes` CHANGELOG line with the verb-local pure-addition rule (see the first alternative). That design change also resolves warnings 2 and 3, which were about the `.gitattributes` line's side effects on `wrap apply`, `land` and `merge` and its clash with the file's own rewritten-in-place rule.
- Folded warnings: an exact stage set from a before/after `git diff --name-only` record, never `git add -u` (1); the main checkout refused like `wrap land` (1); `-c rerere.enabled=false -c rebase.updateRefs=false` on every rebase call (4); exit 64 for a non-worktree path, matching `wrap land` (5); T1 split into preflight, stop loop and final regeneration (6); tests for ABORT FAILED, the stop bound, `index.lock` and fetch failure (7); step 10 wired to call the verb before its push (8).
- No verb-local union resolver: git resolves declared union files during a rebase (checked on git 2.55, including a declaration added by an earlier pick of the same branch).
- The generated rule is one hardcoded pair gated on the generator's presence, with a `ponytail:` comment naming the knob as the upgrade path.
- The final regeneration commits, because a FEATURES left stale after the rebase fails `tests/test-meta.sh` and the pre-push ship-gate.
- No dry-run: the only write is the local branch rewrite, recoverable from the printed old tip or the reflog.
