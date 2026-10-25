# Proof of done: ci-green-round-two

## What changed

Run 40224820774 (master c04aa302) failed `test-lanes-data` and `test-tool-policy-guard` on ubuntu-latest and two suites on macos-latest at their time ceilings. `ubuntu-latest` is now Ubuntu 26.04 (job log: `Image: ubuntu-26.04`): uutils coreutils and a multibyte-aware awk. Both ubuntu failures reproduce in an `ubuntu:26.04` container. Per-suite cause and fix: `docs/implementation-notes/ci-green-round-two.md`.

## Gate table

| Claim | Evidence |
|---|---|
| row 21 fails on 26.04 before the fix and passes after | baseline blocks, container block |
| lanes-data fails with a multibyte awk before the fix and passes after | baseline block, gawk blocks, negative control 2 |
| the macOS floor lifts a low ceiling, keeps a high one, ignores empty or junk | test-run-all-timeout block, negative control 1 |
| no regression | `run-all.sh --changed` block, full `--all` on 26.04 |

## Baseline (before the fixes)

```
Command: docker run --rm --init -e CI=true -e LANG=C.UTF-8 -v "$CLONE":/src:ro kit-ci-2604 bash -c 'sudo apt-get install -y -qq gawk && sudo update-alternatives --set awk /usr/bin/gawk && cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-tool-policy-guard.sh'   (at c04aa302)
Exit: 1
Output:
  FAIL row 21: the module table maps the hook into the advisor module (order-tolerant)
Verdict: FAIL (the baseline this branch fixes)
```

```
Command: set -uo pipefail; for i in $(seq 200); do bash -c "source lib/config/modules.sh; kit_module_hooks advisor" | tr ' ' '\n' | grep -qxF tool-policy-guard.sh || n=$((n+1)); done   (ubuntu:26.04, uutils tr)
Exit: 0
Output:
pipefail failed 151/200
Verdict: FAIL (the pipeline loses the race in 151 of 200 runs; the same loop on 24.04 with GNU tr: 0 of 600)
```

```
Command: PATH="$GAWKDIR:$PATH" LC_ALL=en_US.UTF-8 bash tests/test-lanes-data.sh   (at c04aa302; $GAWKDIR holds an awk symlink to gawk 5.4)
Exit: 1
Output:
FAIL exempt-reader-rejects:  [valid crlf record '']
Verdict: FAIL (the baseline this branch fixes)
```

## Run blocks after the fixes

```
Command: docker run --rm --init -e CI=true -e LANG=C.UTF-8 -v "$CLONE":/src:ro kit-ci-2604 bash -c 'sudo apt-get install -y -qq gawk && sudo update-alternatives --set awk /usr/bin/gawk && cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-tool-policy-guard.sh'
Exit: 0
Output:
Passed: 25 / 25
All tool-policy-guard contract tests passed.
Verdict: PASS
```

```
Command: docker run --rm --init -e CI=true -e LANG=C.UTF-8 -v "$CLONE":/src:ro kit-ci-2604 bash -c 'sudo apt-get install -y -qq gawk && sudo update-alternatives --set awk /usr/bin/gawk && cp -a /src ~/kit && cd ~/kit && git config --global --add safe.directory "*" && bash tests/test-lanes-data.sh'
Exit: 0
Output:
PASS floor-data-loss-sqli-big-head (192ms, 5888925 bytes)
PASS kit-own-session-not-auth
Verdict: PASS
```

```
Command: PATH="$GAWKDIR:$PATH" LC_ALL=en_US.UTF-8 bash tests/test-lanes-data.sh
Exit: 0
Output:
PASS floor-data-loss-sqli-big-head (549ms, 5888925 bytes)
PASS kit-own-session-not-auth
Verdict: PASS
```

```
Command: bash tests/test-run-all-timeout.sh
Exit: 0
Output:
  ok: green run leaves the log root untouched
test-run-all-timeout: all 11 passed
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed origin/master --time
Exit: 0
Output:
  7s test-gate-opt-out
run-all: all 30 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

```
Command: CI=true LANG=C.UTF-8 bash tests/run-all.sh --all   (ubuntu:26.04 container, gawk as awk)
Exit: 1
Output:
run-all: 261 suites, 1 at a time, 3 serial
run-all: FAILED -> test-flick
run-all: 261 suites run, 1 skipped for missing tooling
Verdict: PASS WITH ONE KNOWN CONTAINER-ONLY RED (test-flick, a ps timing assertion; see the implementation notes)
```

## Negative controls

Run after the fixes were committed. Control 1 disables the floor; control 2 restores the byte-wise BOM strip and runs under gawk in a UTF-8 locale. Row 21 has no host-side control: a macOS Mac has no uutils `tr`, so its evidence is the 151-of-200 baseline and the container block above.

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-run-all-timeout.sh" "sed -i.bak 's/RUN_ALL_TIMEOUT_FLOOR_SECS:-}\" in/RUN_ALL_TIMEOUT_FLOOR_SECS_OFF:-}\" in/' tests/run-all.sh && rm -f tests/run-all.sh.bak"   (the floor never applies)
Command: bash tests/test-run-all-timeout.sh
Exit: 0 (green before mutation)
Output:
    ok: listed suite 900, unlisted 300, explicit RUN_ALL_TIMEOUT_SECS wins for all
  [7b] RUN_ALL_TIMEOUT_FLOOR_SECS raises a low listed ceiling, never lowers a high one; empty or junk is ignored; the explicit override still wins
    ok: floor 300: light 60 -> 300, heavy 900 stays, unlisted 300 stays; empty and junk leave 60; explicit 7 wins
  [8] a suite over its listed ceiling prints TIMEOUT with that limit, not the global one
    ok: TIMEOUT (1s) from the data file, no FAILED line
  [9] a failed suite's full output is kept, including a cause line that never says FAIL
    ok: kept file holds the cause line the summary dropped, and its path is printed
  [10] a passing run creates no run-all dir
    ok: green run leaves the log root untouched
  test-run-all-timeout: all 11 passed

Mutation: sed -i.bak 's/RUN_ALL_TIMEOUT_FLOOR_SECS:-}" in/RUN_ALL_TIMEOUT_FLOOR_SECS_OFF:-}" in/' tests/run-all.sh && rm -f tests/run-all.sh.bak
Changed: tests/run-all.sh
Exit: 1 (under mutation, RED expected)
Output:
    ok: listed suite 900, unlisted 300, explicit RUN_ALL_TIMEOUT_SECS wins for all
  [7b] RUN_ALL_TIMEOUT_FLOOR_SECS raises a low listed ceiling, never lowers a high one; empty or junk is ignored; the explicit override still wins
    FAIL: light=60 heavy=900 unlisted=300 empty=60 junk=60 explicit=7
  [8] a suite over its listed ceiling prints TIMEOUT with that limit, not the global one
    ok: TIMEOUT (1s) from the data file, no FAILED line
  [9] a failed suite's full output is kept, including a cause line that never says FAIL
    ok: kept file holds the cause line the summary dropped, and its path is printed
  [10] a passing run creates no run-all dir
    ok: green run leaves the log root untouched
  test-run-all-timeout: 10 passed, 1 FAILED

Restore: git checkout HEAD -- tests/run-all.sh
Exit: 0 (green after restore)
Verdict: PASS
```

```
Command: bash lib/gate/negctl.sh "$PWD" 'PATH="$GAWKDIR:$PATH" LC_ALL=en_US.UTF-8 bash tests/test-lanes-data.sh' "sed -i.bak ... lib/gate/lane-data.sh && rm -f lib/gate/lane-data.sh.bak"   (restore substr(line, 1, 3) == BOM)
Command: PATH="/private/tmp/claude-501/-Users-tieubao-workspace-tieubao-ops-toolkit/ec4ab502-2444-4394-bd5d-3a50deac26b5/scratchpad/m/gawkdir:$PATH" LC_ALL=en_US.UTF-8 bash tests/test-lanes-data.sh
Exit: 0 (green before mutation)
Output:
  PASS floor-data-loss-sqli-optin
  PASS floor-data-loss-sqli-payload
  PASS floor-data-loss-sqli-tab-path
  PASS floor-data-loss-sqli-review-repros
  PASS floor-data-loss-sqli-awk-fails
  PASS ship-sqli-skip-visible
  PASS floor-data-loss-sqli-long-line (394ms, 168927 bytes)
  PASS floor-data-loss-sqli-many-lines (967ms for 30000 lines)
  PASS floor-data-loss-sqli-big-head (589ms, 5888925 bytes)
  PASS kit-own-session-not-auth

Mutation: sed -i.bak 's/index(line, BOM) == 1) line = substr(line, 1 + length(BOM))/substr(line, 1, 3) == "\\357\\273\\277") line = substr(line, 4)/' lib/gate/lane-data.sh && rm -f lib/gate/lane-data.sh.bak
Changed: lib/gate/lane-data.sh
Exit: 1 (under mutation, RED expected)
Output:
  PASS floor-data-loss-sqli-optin
  PASS floor-data-loss-sqli-payload
  PASS floor-data-loss-sqli-tab-path
  PASS floor-data-loss-sqli-review-repros
  PASS floor-data-loss-sqli-awk-fails
  PASS ship-sqli-skip-visible
  PASS floor-data-loss-sqli-long-line (371ms, 168927 bytes)
  PASS floor-data-loss-sqli-many-lines (1125ms for 30000 lines)
  PASS floor-data-loss-sqli-big-head (674ms, 5888925 bytes)
  PASS kit-own-session-not-auth

Restore: git checkout HEAD -- lib/gate/lane-data.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Reproduce

```
# image kit-ci-2604: FROM ubuntu:26.04 + jq git python3 python3-yaml python3-pip curl ca-certificates ripgrep shellcheck
#   sqlite3 lsof procps file xz-utils unzip zip rsync psmisc sudo tzdata make gcc locales, pip install uv,
#   user runner (uid 1001, passwordless sudo), USER runner
CLONE=~/.cache/kit-ci/kit      # a git clone of this worktree with master and origin/master at the base commit
GAWKDIR=$(mktemp -d); ln -s "$(command -v gawk)" "$GAWKDIR/awk"
```

## Rollback

Revert the commits on `fix/ci-green-round-two`. They touch two tests, `lib/gate/lane-data.sh`, `tests/run-all.sh` and `.github/workflows/test.yml`. Nothing is deployed.
