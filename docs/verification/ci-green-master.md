# Proof of done: ci-green-master

## What changed

The `test` workflow failed 13 suites on ubuntu-latest and 5 on macos-latest in run 40213719424 (head 2892b84c). Every red suite is fixed at its root: tests that assumed BSD tools or macOS-only fixtures were corrected so they still check their claim, and four product defects they exposed were fixed. Per-suite cause, fix and evidence: `docs/implementation-notes/ci-green-master.md`.

## Gate table

| Claim | Evidence |
|---|---|
| the 13 ubuntu suites pass on a runner-like Linux container | container run blocks |
| the 5 macOS suites pass, including with no `timeout` on PATH | macOS run blocks |
| the fixes are load-bearing | two negative controls |
| fixed product code keeps its macOS behavior | macOS run blocks (harvest-sweep, hook-util, intake-sweep-parity, run-all, test-affected) |
| test-lanes-data and test-tool-policy-guard pass; their baseline failure is not reproduced | both blocks, and the note in the implementation notes |

## Baseline (before the fixes)

```
Command: docker run --rm --init -e CI=true -v "$CLONE":/src:ro kit-ci-ubuntu bash -c 'cp -a /src ~/kit && cd ~/kit && bash tests/test-hook-util.sh'   (at 5690c702, master before this branch)
Exit: 1
Output:
  FAIL hu_mtime under a GNU-style stat: want '1577934245' got ''
  FAIL hu_throttled under a GNU-style stat still throttles: want 'throttled' got 'run'
hook-util: 28 passed, 2 failed
Verdict: FAIL (the baseline this branch fixes)
```

## macOS run blocks

Host: this Mac, Homebrew bash 5.3, GNU `timeout` on PATH. Each suite run alone.

### test-board-brief

```
Command: bash tests/test-board-brief.sh
Exit: 0
Output:
case verb:
  ok   board brief run --help
board-brief: 110 passed, 0 failed
Verdict: PASS
```

### test-board-health

```
Command: bash tests/test-board-health.sh
Exit: 0
Output:
case verb (board health reaches the script):
  ok   board health run --help
board-health: 97 passed, 0 failed
Verdict: PASS
```

### test-board-hermes

```
Command: bash tests/test-board-hermes.sh
Exit: 0
Output:
case verb:
  ok   board hermes link --help
board-hermes: 79 passed, 0 failed
Verdict: PASS
```

### test-board-sweep-post

```
Command: bash tests/test-board-sweep-post.sh
Exit: 0
Output:
  ok   no --cluster -> 64
  ok   no --poster (and no --dry-run) -> 64
PASS=32 FAIL=0
Verdict: PASS
```

### test-staging-one-writer

```
Command: bash tests/test-staging-one-writer.sh
Exit: 0
Output:
  PASS both hook blocks present
  PASS an unwritable path exits non-zero
== 38 run, 38 passed, 0 failed ==
Verdict: PASS
```

### test-hook-util

```
Command: bash tests/test-hook-util.sh
Exit: 0
Output:
hook-util: 31 passed, 0 failed
Verdict: PASS
```

### test-flick

```
Command: bash tests/test-flick.sh
Exit: 0
Output:
  ok: jev: the request body, unchanged
  ok: jev: flick body output, unchanged
flick: 346 passed, 0 failed
Verdict: PASS
```

### test-harvest-sweep

```
Command: bash tests/test-harvest-sweep.sh
Exit: 0
Output:
=== Results ===
Passed: 637 / 637
All harvest sweep tests passed.
Verdict: PASS
```

### test-wrap-apply

```
Command: bash tests/test-wrap-apply.sh
Exit: 0
Output:
  PASS pinned config: agent2 is proven merged after that fetch
  PASS pinned config: agent2 is gone
test-wrap-apply: all 309 passed
Verdict: PASS
```

### test-intake-sweep-parity

```
Command: bash tests/test-intake-sweep-parity.sh
Exit: 0
Output:
intake-sweep parity: 160 passed, 0 failed
Verdict: PASS
```

### test-no-personal-paths

```
Command: bash tests/test-no-personal-paths.sh
Exit: 0
Output:
ok - no operator path or hostname anywhere in the tree
Passed: 3 / 3
All no-personal-paths tests passed.
Verdict: PASS
```

### test-proof-negctl

```
Command: bash tests/test-proof-negctl.sh
Exit: 0
Output:
warning: templates not found in ~/.git_template
  ok: subdir root restored, tree clean
test-proof-negctl: all 56 passed
Verdict: PASS
```

### test-run-all-changed

```
Command: bash tests/test-run-all-changed.sh
Exit: 0
Output:
  ok: CI=true runs the full glob
  ok: KIT_RUN_ALL=1 runs the full glob
test-run-all-changed: all 12 passed
Verdict: PASS
```

### test-run-all-time

```
Command: bash tests/test-run-all-time.sh
Exit: 0
Output:
[4] without --time the output is byte-identical to the version before the flag
  ok: no --time, no change
test-run-all-time: all 4 passed
Verdict: PASS
```

### test-run-all-timeout

```
Command: bash tests/test-run-all-timeout.sh
Exit: 0
Output:
[10] a passing run creates no run-all dir
  ok: green run leaves the log root untouched
test-run-all-timeout: all 10 passed
Verdict: PASS
```

### test-run-all-times

```
Command: bash tests/test-run-all-times.sh
Exit: 0
Output:
[12f] a suite that is still red after the rerun keeps --failed exiting 1
  ok: only the red suite ran, red stays red, exit 1 both times
run-all-times: 37 passed, 0 failed
Verdict: PASS
```

### test-run-all-tmpdir

```
Command: bash tests/test-run-all-tmpdir.sh
Exit: 0
Output:
[2] an uncreatable $TMPDIR fails loudly, runs nothing
  ok: non-zero exit, one clear line, no false pass
test-run-all-tmpdir: all 2 passed
Verdict: PASS
```

### test-lanes-data

```
Command: bash tests/test-lanes-data.sh
Exit: 0
Output:
PASS floor-data-loss-sqli-many-lines (928ms for 30000 lines)
PASS floor-data-loss-sqli-big-head (501ms, 5888925 bytes)
PASS kit-own-session-not-auth
Verdict: PASS
```

### test-tool-policy-guard

```
Command: bash tests/test-tool-policy-guard.sh
Exit: 0
Output:
=== Results ===
Passed: 25 / 25
All tool-policy-guard contract tests passed.
Verdict: PASS
```

## macOS with no `timeout` on PATH

The stock-macOS case. `$NOTIMEOUT` is a directory of symlinks to every tool on the real PATH except `timeout` and `gtimeout` (built by the loop in the Reproduce section).

### test-test-affected

```
Command: PATH="$NOTIMEOUT" bash tests/test-test-affected.sh
Exit: 0
Output:
  ok: a red suite inside its limit is still FAIL
  ok: a red suite is not reported as TIMEOUT
test-test-affected: 74 passed, 0 failed
Verdict: PASS
```

### test-test-affected-cache

```
Command: PATH="$NOTIMEOUT" bash tests/test-test-affected-cache.sh
Exit: 0
Output:
  ok: --list appends nothing
  ok: history grew across runs
test-affected-cache: 17 passed, 0 failed
Verdict: PASS
```

### test-test-affected-parallel

```
Command: PATH="$NOTIMEOUT" bash tests/test-test-affected-parallel.sh
Exit: 0
Output:
  ok: a failed suite is never cached
  ok: second run: 3 cached, the red one re-runs
test-affected-parallel: 41 passed, 0 failed
Verdict: PASS
```

## Ubuntu container run blocks

Image `kit-ci-ubuntu` (recipe in the Reproduce section), checkout `$CLONE` (a clone of this worktree), one container per batch, suites run in the order below.

### test-board-brief

```
Command: docker run --rm --init -e CI=true -v "$CLONE":/src:ro kit-ci-ubuntu bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-board-brief.sh'
Exit: 0
Output:
case verb:
  ok   board brief run --help
board-brief: 110 passed, 0 failed
Verdict: PASS
```

### test-board-health

```
Command: docker run --rm --init -e CI=true -v "$CLONE":/src:ro kit-ci-ubuntu bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-board-health.sh'
Exit: 0
Output:
case verb (board health reaches the script):
  ok   board health run --help
board-health: 97 passed, 0 failed
Verdict: PASS
```

### test-board-hermes

```
Command: docker run --rm --init -e CI=true -v "$CLONE":/src:ro kit-ci-ubuntu bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-board-hermes.sh'
Exit: 0
Output:
case verb:
  ok   board hermes link --help
board-hermes: 79 passed, 0 failed
Verdict: PASS
```

### test-board-sweep-post

```
Command: docker run --rm --init -e CI=true -v "$CLONE":/src:ro kit-ci-ubuntu bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-board-sweep-post.sh'
Exit: 0
Output:
  ok   no --cluster -> 64
  ok   no --poster (and no --dry-run) -> 64
PASS=32 FAIL=0
Verdict: PASS
```

### test-flick

```
Command: docker run --rm --init -e CI=true -v "$CLONE":/src:ro kit-ci-ubuntu bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-flick.sh'
Exit: 0
Output:
  ok: jev: the request body, unchanged
  ok: jev: flick body output, unchanged
flick: 344 passed, 0 failed
Verdict: PASS
```

### test-harvest-sweep

```
Command: docker run --rm --init -e CI=true -v "$CLONE":/src:ro kit-ci-ubuntu bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-harvest-sweep.sh'
Exit: 0
Output:
=== Results ===
Passed: 637 / 637
All harvest sweep tests passed.
Verdict: PASS
```

### test-hook-util

```
Command: docker run --rm --init -e CI=true -v "$CLONE":/src:ro kit-ci-ubuntu bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-hook-util.sh'
Exit: 0
Output:
hook-util: 31 passed, 0 failed
Verdict: PASS
```

### test-intake-sweep-parity

```
Command: docker run --rm --init -e CI=true -v "$CLONE":/src:ro kit-ci-ubuntu bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-intake-sweep-parity.sh'
Exit: 0
Output:
intake-sweep parity: 160 passed, 0 failed
Verdict: PASS
```

### test-lanes-data

```
Command: docker run --rm --init -e CI=true -v "$CLONE":/src:ro kit-ci-ubuntu bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-lanes-data.sh'
Exit: 0
Output:
PASS floor-data-loss-sqli-many-lines (109ms for 30000 lines)
PASS floor-data-loss-sqli-big-head (171ms, 5888925 bytes)
PASS kit-own-session-not-auth
Verdict: PASS
```

### test-no-personal-paths

```
Command: docker run --rm --init -e CI=true -v "$CLONE":/src:ro kit-ci-ubuntu bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-no-personal-paths.sh'
Exit: 0
Output:
ok - no operator path or hostname anywhere in the tree
Passed: 3 / 3
All no-personal-paths tests passed.
Verdict: PASS
```

### test-staging-one-writer

```
Command: docker run --rm --init -e CI=true -v "$CLONE":/src:ro kit-ci-ubuntu bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-staging-one-writer.sh'
Exit: 0
Output:
  PASS both hook blocks present
  PASS an unwritable path exits non-zero
== 38 run, 38 passed, 0 failed ==
Verdict: PASS
```

### test-tool-policy-guard

```
Command: docker run --rm --init -e CI=true -v "$CLONE":/src:ro kit-ci-ubuntu bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-tool-policy-guard.sh'
Exit: 0
Output:
=== Results ===
Passed: 25 / 25
All tool-policy-guard contract tests passed.
Verdict: PASS
```

### test-wrap-apply

```
Command: docker run --rm --init -e CI=true -v "$CLONE":/src:ro kit-ci-ubuntu bash -c 'cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-wrap-apply.sh'
Exit: 0
Output:
  PASS pinned config: agent2 is proven merged after that fetch
  PASS pinned config: agent2 is gone
test-wrap-apply: all 309 passed
Verdict: PASS
```

## Negative controls

Run after the fixes were committed. Control 1 removes the perl fallback from the new timeout helper, which is the stock-macOS case; the three test-affected suites go red. Control 2 restores the absolute home path in the record that tripped `test-no-personal-paths`. Both restored cleanly and went green again.

```
Command: bash lib/gate/negctl.sh "$PWD" "PATH=$NOTIMEOUT bash tests/test-test-affected.sh" "sed -i.bak 's/elif command -v perl >\/dev\/null 2>&1; then/elif false; then/' tests/lib/timeout.sh && rm -f tests/lib/timeout.sh.bak"   (kit_timeout loses its perl fallback)
Command: PATH=/private/tmp/claude-501/-Users-tieubao-workspace-tieubao-ops-toolkit/ec4ab502-2444-4394-bd5d-3a50deac26b5/scratchpad/m/notimeout bash tests/test-test-affected.sh
Exit: 0 (green before mutation)
Output:
    ok: a suite over its listed limit prints TIMEOUT with the limit
    ok: a timeout is never reported as FAIL
    ok: the summary counts the timeout
    ok: a timeout exits non-zero
    ok: TEST_AFFECTED_TIMEOUT_SECS overrides the data file
    ok: a suite with no entry gets the 300s default
    ok: a red suite inside its limit is still FAIL
    ok: a red suite is not reported as TIMEOUT
  
  test-test-affected: 74 passed, 0 failed

Mutation: sed -i.bak 's/elif command -v perl >\/dev\/null 2>&1; then/elif false; then/' tests/lib/timeout.sh && rm -f tests/lib/timeout.sh.bak
Changed: tests/lib/timeout.sh
Exit: 1 (under mutation, RED expected)
Output:
  PASS tests/test-a.sh
  PASS tests/test-kt-env.sh
  test-affected: 2 selected, 2 pass, 0 cached, 0 fail, 0 timeout, 0 uncovered)
    FAIL: exit 0 despite TIMEOUT
    ok: TEST_AFFECTED_TIMEOUT_SECS overrides the data file
    ok: a suite with no entry gets the 300s default
    ok: a red suite inside its limit is still FAIL
    ok: a red suite is not reported as TIMEOUT
  
  test-test-affected: 71 passed, 3 failed

Restore: git checkout HEAD -- tests/lib/timeout.sh
Exit: 0 (green after restore)
Verdict: PASS
```

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-no-personal-paths.sh" "sed -i.bak 's#~/.git_template#<home>/.git_template#' docs/verification/front-door-rewrite.md && rm -f docs/verification/front-door-rewrite.md.bak"   (put the absolute home path back in the record)
Command: bash tests/test-no-personal-paths.sh
Exit: 0 (green before mutation)
Output:
  warning: templates not found in ~/.git_template
  ok - adopt renders no render-time install path into the consumer repo
  ok - rendered files still point at the kit (portable ~ or $HOME form)
  ok - no operator path or hostname anywhere in the tree
  
  Passed: 3 / 3
  All no-personal-paths tests passed.

Mutation: sed -i.bak 's#~/.git_template#~/.git_template#' docs/verification/front-door-rewrite.md && rm -f docs/verification/front-door-rewrite.md.bak
Changed: docs/verification/front-door-rewrite.md
Exit: 1 (under mutation, RED expected)
Output:
  warning: templates not found in ~/.git_template
  ok - adopt renders no render-time install path into the consumer repo
  ok - rendered files still point at the kit (portable ~ or $HOME form)
  NOT ok - operator path/hostname still present:
  docs/verification/front-door-rewrite.md:91:  warning: templates not found in ~/.git_template
  
  Passed: 2 / 3
  1 test(s) failed.

Restore: git checkout HEAD -- docs/verification/front-door-rewrite.md
Exit: 0 (green after restore)
Verdict: PASS
```

## Reproduce

```
# image (Dockerfile): ubuntu:24.04 + git from ppa:git-core + jq git python3 python3-yaml python3-pip curl
#   ripgrep shellcheck sqlite3 lsof procps file xz-utils unzip zip rsync psmisc sudo tzdata make gcc locales
#   (locale-gen en_US.UTF-8), pip install uv, user runner (uid 1001), USER runner
CLONE=~/.cache/kit-ci/kit      # a git clone of this worktree, with master and origin/master at the base commit
# a PATH with no timeout:
NOTIMEOUT=$(mktemp -d); IFS=:; for d in $PATH; do for f in "$d"/*; do b="${f##*/}"
  case "$b" in timeout|gtimeout) continue;; esac
  [ -f "$f" ] && [ -x "$f" ] && [ ! -e "$NOTIMEOUT/$b" ] && ln -s "$f" "$NOTIMEOUT/$b"; done; done
```

## Rollback

Revert the commits on `fix/ci-green-master`. They touch tests, three product files (`lib/reflect/hook-util.sh`, `deploy/macos/harvest-sweep/`, `bin/test-affected`), `tests/run-all.sh`, one new helper (`tests/lib/timeout.sh`) and two quoted lines in verification records. Nothing is deployed and no state is written outside the tree.
