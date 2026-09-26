# SPEC-318: spec-next reserve keys by repository, not checkout folder

**Status:** VALIDATED
Lane: full
Type: bug
**Proof:** `docs/verification/spec-reserve-worktree.md`; `tests/test-spec-reserve.sh`, T1, T7, T12 and T20-T23.

## Problem

`lib/spec/spec-next.sh reserve` writes one ledger line per claim, `<iso> | RESERVE | num=NNN repo=<key>`. The key is `basename` of `git rev-parse --show-toplevel`. A git worktree at `<repo>/.claude/worktrees/<slug>` has its own toplevel, so its key is the slug. Three worktrees of dwarves-kit each read zero live reservations under their own key and all claimed SPEC-315 within three minutes (`spec-reservations.log`: `repo=negctl-hint`, `repo=prompt-lens-eval`, `repo=land-ship-record`, plus an earlier `repo=red-suites-on-master num=315`). The mutex worked. The key split one repo into four.

A second gap sits in `_scan_numbers()`. It lists `$ROOT/docs/specs` for the current checkout only. Branch names and commit subjects already come from the shared ref store, so every worktree sees them. An uncommitted spec file in a sibling worktree stays invisible.

## Contract

- The reservation key is the physical absolute path of the repository's common git dir, with a trailing `/.git` removed: from `$ROOT`, `cd "$(git rev-parse --git-common-dir)" && pwd -P`, then `${key%/.git}`. The main checkout and every linked worktree resolve to the same path. For a normal repo the key is the main checkout's directory, for a bare repo it is the bare dir.
- Outside a git repo the key falls back to the toplevel (`pwd`), as the old code did.
- `_scan_numbers()` lists `docs/specs` in every worktree that `git worktree list --porcelain` names, the current one included. When that call fails it lists `$ROOT/docs/specs` alone, as before.
- The ledger line format stays `<iso> | RESERVE | num=NNN repo=<key>`. `repo=` stays the trailing field, and the anchored suffix match stays.
- `next` and `check` keep their output and exit codes. With an empty ledger and no sibling worktree they print what they printed before.

Legacy lines: a line written by the old code carries `repo=<folder name>`. The new key is an absolute path, so no legacy line matches it. A legacy line reads as a foreign repo's line: it never counts as live for any caller, the parser skips nothing new, and the cross-repo TTL prune drops it 24 hours after it was written. During those 24 hours a legacy claim from before the upgrade is not honored by the new code. The mitigation is the worktree spec scan: a claim whose spec file exists in any worktree reads as taken through the scan, key or no key.

## Picture

```
 before                                        after
 ------                                        -----
 <repo>/                 key=<repo name>       <repo>/                 key=<abs path of repo>
 <repo>/.claude/worktrees/a  key=a             <repo>/.claude/worktrees/a  key=<abs path of repo>
 <repo>/.claude/worktrees/b  key=b             <repo>/.claude/worktrees/b  key=<abs path of repo>
       |                                             |
       v                                             v
 spec-reservations.log (one per machine)       spec-reservations.log
   num=315 repo=a                                num=315 repo=/x/<repo>
   num=315 repo=b   <- collision                 num=316 repo=/x/<repo>   <- b sees a's claim

 _scan_numbers(): docs/specs of $ROOT only     _scan_numbers(): docs/specs of every
                                               `git worktree list` entry + branches + log
```

## Design

Design-bearing: the key rule is a data-model change to a machine-global ledger, and three rules were viable.

Flow of one `reserve` after the change:

```
 caller cwd (any worktree)
      |
      v
 git rev-parse --git-common-dir, pwd -P ---> key = /abs/<repo>  (same in every worktree)
      |
      v
 mkdir-mutex on spec-reservations.log.lock
      |
      v
 next():  _scan_numbers  = docs/specs of each worktree
                         + branch names (shared refs)
                         + last 200 commit subjects (shared refs)
          _scan_pr_numbers (unchanged)
          _reservations  = lines whose trailing field == "repo=<key>", within TTL
      |
      v
 append "num=<max+1> repo=<key>", prune (TTL: all repos; realized: this key), unlock
```

Approaches considered:

| Approach | Unique per repo | Same across worktrees | Why not / why |
|---|---|---|---|
| `basename` of the toplevel (current) | no | no | The bug. |
| `basename` of the main checkout (dirname of the common dir) | no | yes | Two clones named `dwarves-kit` in different parents share a key. Shared liveness only over-reserves, but the realized-prune of repo A can drop repo B's live line when A's scan holds B's number, and B then hands that number out twice. |
| `origin` remote URL | yes for pushed repos | yes | A repo with no remote, or two clones of one remote on one machine, breaks it. Two clones of one remote would share a key and a counter while scanning different trees. |
| Absolute common-dir path (chosen) | yes | yes | One `git rev-parse` call, no network, no config. The path is the identity git itself uses to tie worktrees together. |

The key is longer and less readable in the log than a folder name. The log is a machine ledger, so readability is not a contract.

Worktree spec scan: `git worktree list --porcelain` is one local git call, then one `ls` per worktree. A repo with 30 worktrees pays 30 `ls` calls per scan, well under the cost of the existing `git log --all`. A worktree whose directory is gone (prunable) makes `ls` fail, which the existing `|| true` absorbs. So the fold-in is cheap and ships in this change.

Git version: the key avoids `--path-format=absolute` (git 2.31+). An older git echoes an unknown flag back as output, and `--git-common-dir` prints a relative `.git` in the main checkout but an absolute path in a worktree, so the two keys would differ. `cd` plus `pwd -P` makes the path absolute on any git that has `--git-common-dir` (2.5+) and resolves symlinks such as macOS `/var` to `/private/var` the same way from every checkout.

## Failure modes

| Class | Detection | Mitigation |
|---|---|---|
| Two worktrees of one repo reserve at once | same key, one mutex | the second caller reads the first's line and takes max+1 (T20) |
| Two repos share a folder name | different absolute paths | independent counters, no cross-prune (T21) |
| Legacy `repo=<name>` line in the ledger | key never matches a path | ignored for liveness, TTL-pruned at 24h; a spec file in any worktree still reads as taken (T22, T23) |
| Repo moved or renamed on disk | key changes | the old path's lines stop counting; they expire at 24h; same window as legacy lines |
| A sibling worktree deleted mid-scan | `ls` fails | `|| true`, the scan continues |
| `git worktree list` fails | non-zero exit | fall back to `$ROOT/docs/specs` alone |
| Not a git repo | `rev-parse` fails | key = toplevel fallback (`pwd`), as before |
| Uncommitted spec in a sibling worktree | worktree scan | its number reads as taken and a matching live reservation is pruned as realized |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: tests first | `tests/test-spec-reserve.sh` | T20-T23 go red on the old key; T1, T7, T12 assert the new key |
| T2: key + scan | `lib/spec/spec-next.sh` | the Contract above; every T-case green |
| T3: docs | `docs/CHANGELOG.md`, `docs/FEATURES.md` (regenerated) | one `[Unreleased]` line under Fixed |

## Test plan

| Case | Setup | Expected |
|---|---|---|
| T1 key shape | one repo, one reserve | line ends `repo=<abs repo path>` |
| T7 expired line | 1970 line under the new key | not counted, pruned by the next reserve |
| T12 anchored match | live line for `<path>` while the repo is `<path>-bar` | not folded in |
| T20 two worktrees, concurrent | repo + two linked worktrees, `reserve` from both in parallel | two different numbers, both lines carry the same key |
| T21 same folder name, two repos | `/a/same` and `/b/same`; A reserves twice | B's `next` ignores A (006) and B's reserve keeps A's lines |
| T22 legacy line | live `repo=<folder name>` line | parsing does not break; `next` ignores it; a TTL-expired legacy line is pruned |
| T23 sibling worktree spec | uncommitted `SPEC-009-x.md` in worktree b | `next` from worktree a prints 010 |
| Existing T2-T19 | unchanged | green |

Negative control: `lib/gate/negctl.sh` rewrites the key line back to `basename "$ROOT"`. T20 and T21 must go red.

## Verification

`bash tests/test-spec-reserve.sh` exits 0. `bash tests/run-all.sh --changed` exits 0.

## After state

Every worktree of one repo draws SPEC numbers from one counter, and a spec file written in any worktree blocks its number for all of them. Two repos that share a folder name no longer share a counter. Not covered: two machines drawing numbers for one repo; each machine has its own ledger, and only the open-PR scan links them.

## Decision Log

- Chose the absolute common-dir path over the main checkout's folder name: the folder name keeps the same-name collision the brief asked to consider.
- Validate (Reviewer 3): dropped `--path-format=absolute` for `cd` plus `pwd -P`; on git older than 2.31 the flag breaks the key.
- Legacy lines are not translated or honored; the 24h TTL retires them and the worktree spec scan covers a claim that already has a file.
