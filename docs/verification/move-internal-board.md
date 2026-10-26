# Verification: move-internal-board

The kit's internal state (`_meta/BACKLOG.md`, `_meta/backlog-staging.md`, `_meta/megagoals/`) moves out of the public tree into the private `dwarves-kit-internal` repo. The kit tree gitignores `/_meta`; a maintainer links the private copy in as a local `_meta` symlink. Kit readers keep working through the symlink and degrade to one clear line when `_meta/` is absent.

## What changed

| Area | Change |
|---|---|
| `_meta/` | `git rm -r`; `/_meta` added to `.gitignore` |
| `lib/board/backlog.sh` | `dedupe-all <file>` and `lint <file>` no longer need the default board; a verb that does prints `no board at <path> (...)` and exits 1 |
| `tests/test-board-add.sh`, `test-meta-spec-depth.sh`, `test-meta-vmodel-dispatch.sh` | stop reading the real board; use a fixture or `backlog.sh states` |
| `commands/start.md`, `next.md`, `assign.md` | say to skip or stop when the checkout has no `_meta/BACKLOG.md` |
| `.kit.toml` | the `[sync]` block moves to the private repo's `.kit.toml` |
| `lib/adopt/agents-known.sha256` | regenerated for the new `AGENTS.md` version |
| docs | `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `docs/README.md`, `docs/HISTORY.md`, `docs/reference/project-structure.md` say where the board lives now |

Other readers already tolerate a missing board (checked by running each verb with no `_meta/`): `board work|promote|queue|status|mirror|all|run|sync`, `reflect drain`, `mega status`, `queue watch|run --from-boards`, and the `backlog-stage`, `board-row-gate`, `ship-gate` and `context-readiness` hooks (each tests `-f` first). No hard-path file needed a code change except `.kit.toml`, where the personal `[sync]` block left with the board.

## Absence behavior

| Reader | With no `_meta/` |
|---|---|
| `lib/board/backlog.sh` board, next, get, row, set, add, dedupe | one line `backlog.sh: no board at <path> ...`, exit 1 |
| `backlog.sh` states, `lint <file>`, `dedupe-all <file>` | run, no default board needed |
| `bin/board` single-repo verbs | `board: --backlog-file is required`, exit 64 (unchanged) |
| `board work`, `board run`, `board sync` | one line naming the missing BACKLOG.md (unchanged) |
| `board promote`, `reflect drain` | `no staging file ...; nothing staged`, exit 0 (unchanged) |
| `board queue`, `status`, `mirror`, `all` | `no registry at ...`, exit 1 (unchanged) |
| `mega status <slug>` | `no ROADMAP.md at ...`, exit 1 (unchanged) |
| hooks | silent skip (unchanged) |

## Green runs

### no `_meta/` present (what a fresh public clone sees)

```
Command: bash tests/run-all.sh --changed origin/master
Exit: 0
Output:
test-wrap-merge                                ok
test-wrap-rebase                               ok
lib-session-test-handoffs                      ok
lib-telemetry-smoke                            ok

run-all: all 106 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

```
Command: bash tests/test-meta.sh
Exit: 0
Output:

=== Results ===
Passed: 930 / 930
All meta tests passed.
Verdict: PASS
```

```
Command: bash tests/gauntlet/tier1.sh
Exit: 0
Output:
PASS  shellcheck -x tests/gauntlet/*.sh tests/gauntlet/cleanroom/*.sh tests/gauntlet/deploy/gauntlet-campaign

TIER1: GREEN
Verdict: PASS
```

```
Command: bash tests/run-all.sh --only board
Exit: 0
Output:
test-runs-dashboard                            ok

run-all: all 28 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

```
Command: bash tests/run-all.sh --only reflect
Exit: 0
Output:
test-reflect-propose                           ok

run-all: all 2 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

### a temporary `_meta` symlink to the private clone's `_meta/` (removed before commit)

```
Command: bash tests/run-all.sh --changed origin/master
Exit: 0
Output:
test-wrap-merge                                ok
test-wrap-rebase                               ok
lib-session-test-handoffs                      ok
lib-telemetry-smoke                            ok

run-all: all 106 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

```
Command: bash tests/test-meta.sh
Exit: 0
Output:

=== Results ===
Passed: 930 / 930
All meta tests passed.
Verdict: PASS
```

```
Command: bash tests/gauntlet/tier1.sh
Exit: 0
Output:
PASS  shellcheck -x tests/gauntlet/*.sh tests/gauntlet/cleanroom/*.sh tests/gauntlet/deploy/gauntlet-campaign

TIER1: GREEN
Verdict: PASS
```

```
Command: bash tests/run-all.sh --only board
Exit: 0
Output:
test-runs-dashboard                            ok

run-all: all 28 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

```
Command: bash tests/run-all.sh --only reflect
Exit: 0
Output:
test-reflect-propose                           ok

run-all: all 2 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

Feature registry and tracked-file check (no `_meta/` present):

```
Command: bash lib/registry/feature-registry.sh check docs/reference/FEATURES.md; git ls-files _meta | wc -l
Exit: 0
Output:
feature-registry: docs/reference/FEATURES.md is fresh
0
Verdict: PASS
```

Board verbs with and without `_meta/`: a sweep of the `bin/board`, `bin/reflect`, `bin/mega`, `bin/queue` and `lib/board/*.sh` entry points. With the symlink, `board work`, `board promote`, `backlog.sh board` and `reflect drain` render the real board and staging. Without it each prints a one-line message from the table above and none crashes.

The 113 suites that mention the board ran once with no `_meta/` and once with the symlink; every one exited 0 in both cases (before the final two commits; the final runs above cover the committed tree).

## Negative control

## Negative control (negctl)
Command: bash tests/test-board-add.sh
Exit: 0 (green before mutation)
Output:
  
  == no default board (a public kit clone has no _meta/): one line, never a crash ==
    PASS a verb that needs the default board exits 1
    PASS and names the missing file on one line
    PASS and prints exactly one line
    PASS states needs no board
    PASS lint <file> reads its own file, not the default board
    PASS dedupe-all <file> sweeps its own file with no default board
  
  == 70 run, 70 passed, 0 failed ==

Mutation: git show origin/master:lib/board/backlog.sh > lib/board/backlog.sh
Changed: lib/board/backlog.sh
Exit: 1 (under mutation, RED expected)
Output:
  == no default board (a public kit clone has no _meta/): one line, never a crash ==
    PASS a verb that needs the default board exits 1
    FAIL and names the missing file on one line
    PASS and prints exactly one line
    PASS states needs no board
  backlog.sh: BACKLOG_FILE names no readable file: /var/folders/dr/n3x74rr93kvfjf1873pyjvp80000gn/T/dk-board-add-test.FOMCbu/absent/BACKLOG.md, check the board wrapper's path
    FAIL lint <file> reads its own file, not the default board
    FAIL dedupe-all <file> sweeps its own file with no default board
  
  == 70 run, 67 passed, 3 failed ==

Restore: git checkout HEAD -- lib/board/backlog.sh
Exit: 0 (green after restore)
Verdict: PASS

Reading: with the old `backlog.sh` restored, three assertions of the new absence section go red (the one-line message, `lint <file>`, `dedupe-all <file>`); restoring the new file turns it green again.

## Rollback

`git revert` the commits on `chore/move-internal-board`: the tree gets `_meta/` back and the `.gitignore` line and the `backlog.sh` change go away. The private repo keeps its own copy on `main`; the pre-squash history stays on `archive/master-pre-squash` there. Removing the local `_meta` symlink returns a machine to the public-clone behavior above.
