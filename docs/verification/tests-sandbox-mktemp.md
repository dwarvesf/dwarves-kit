# Verification -- tests-sandbox-mktemp

The kit suite must run inside the Seatbelt sandbox of the ops-toolkit incident-fix host lane, where only the worktree and `$TMPDIR` are writable. macOS `mktemp` and `mktemp -d` with no template, and `mktemp -t name`, ignore `$TMPDIR` and use the per-user `/var/folders` directory. The sandbox denies that directory, so the call fails and the `$(...)` result is empty. Suites then built their fixtures in the current directory or at `/`, and 158 of 231 suites went red. This change gives every mktemp an explicit `"${TMPDIR:-/tmp}/<name>.XXXXXX"` template, stops tests that use an empty result, and adds a guard test.

## Root cause and the safety bug

| Item | Finding |
|---|---|
| Cause | Bare `mktemp -d` returns `""` when `/var/folders` is denied. The failure is silent: callers do not check the status. |
| Safety | `cd ""` succeeds in place, so a suite that did `cd "$(mktemp -d)"` then `git init`, `git switch -c feat/a\|b` ran inside its own cwd. A fixture leaked into a real clone this way. Every test use of the result now ends in `|| exit 1` or `|| return 1`, and the guard rejects `cd "$(mktemp ...)"`. |
| Scope | 460 bare calls in 215 files across tests/, lib/, hooks/ and deploy/; the same template form already existed in about 100 other places. |
| Second class | Fixed scratch paths (`/tmp/vf-*`, `/tmp/kitmod-*`, `/tmp/kitcli-*`, `/tmp/cls-*`) are also denied in the sandbox and race across concurrent runs. Moved under `$TMPDIR`. |
| Third class | `tests/lib/hook-parity.sh` runs the hook under `env -i`, which dropped `$TMPDIR`; it now passes it through. |

## test-wrap-start: why it was red unsandboxed

| Item | Finding |
|---|---|
| Symptom | Control run (lane env, no sandbox): `carry: nothing dirty prints the marker` fails, 60 of 61 pass. The nightly was green. |
| Cause | The lane env sets `GIT_CONFIG_GLOBAL=/dev/null`. The operator's `core.excludesFile` (`~/.gitignore`) is the only thing that hides `.claude/worktrees/`. Without it `git stash push -u` takes the new worktree directory as untracked dirt, so `wrap start --carry` finds something to carry. |
| Reproduction | `GIT_CONFIG_GLOBAL=/dev/null bash tests/test-wrap-start.sh` fails; with the real config it passes. This is a production bug in `lib/wrap/wrap-start.sh` for any account with no global ignore, not a test flaw. |
| Fix | When `.claude/worktrees` is not already ignored, the stash pathspec excludes it. When it is ignored a pathspec naming it makes git refuse, so the plain stash stays. |

```
Command: GIT_CONFIG_GLOBAL=/dev/null bash tests/test-wrap-start.sh
Exit: 0
Output: test-wrap-start: all 61 passed
```

## Reproduction (before)

The lane runs the suite under Claude Code's Seatbelt sandbox (`sandbox.filesystem.allowWrite = [worktree, tmp_dir]`, `denyRead` on `/Users /Volumes /private/tmp /private/var/folders`). This host cannot start a model session for free, so the sandbox is approximated with `sandbox-exec` using the same write allow-list, the same read denies and allows, and the lane session and test env (`TMPDIR`, `GIT_CONFIG_GLOBAL=/dev/null`, placeholder tokens, `KIT_RUN_ALL=1`). Treat the counts as an approximation of the lane, not a lane run.

```
Command: sandbox-exec -f kit.sb env TMPDIR=<tmp> bash tests/test-adopt.sh   (also test-explain, test-lane-telemetry)
Output:  mktemp: mkdtemp failed on /var/folders/.../T/tmp.GVpnf0i2qh: Operation not permitted
         test-adopt        PASS=10 FAIL=46
         test-explain      TOTAL: 14   PASS: 5   FAIL: 9
         test-lane-telemetry  17/67 passed, 50 failed
         the same three, unsandboxed: exit 0
```

Before-count: the finding in ops-toolkit `tools/crew/docs/proof-of-done.md` reports 158 of 231 suites red only in the sandbox, so at most 73 of 231 were green there. That figure was not re-measured here.

## Sandboxed full run (after)

```
Command: lane-run.sh <worktree> <tmp> --all --time   # sandbox-exec + lane env, bash tests/run-all.sh --all
Exit: 1
Output: run-all: 238 suites run, 0 skipped for missing tooling
        202 ok, 36 FAIL, wall 1130s
```

That run was at commit 02fddbf0, before the second and third fix classes and before the registry was regenerated. A targeted sandboxed rerun of the 36 failed suites at the final tree:

| Set | Count |
|---|---|
| Failed in the full run | 36 |
| Pass sandboxed after the later fixes | 12 (includes `test-meta-docs-registry`, which my new test file had made stale, and `test-intake-sweep-parity`, fixed in hook-parity.sh) |
| Still fail sandboxed | 24 |
| Sandboxed suites green, combined | 214 of 238 |

The combined figure joins a full run and a targeted rerun, so it is not one clean run. The 24 that remain are not mktemp failures. All 24 pass unsandboxed in the lane env. Causes seen in their output:

| Cause | Suites |
|---|---|
| `$HOME/.claude/dwarves-kit/kit.toml` unreadable (HOME is denied) | test-config-registry, test-orchestrate-orca, test-proof-verdict-hint |
| uv cache under `$HOME/.cache/uv` | test-sync, test-webcheck, test-bin-forwarders, test-bench |
| `/dev/fd/N` process substitution refused (may be an artifact of the approximation) | test-research-arch-contract, test-research-pair-contract, test-precedent, test-lanes-data |
| process and fs introspection (`lsof`, `ps` pgid) | test-wrap-apply, test-kit-foldin-hooks, test-flick |
| not diagnosed | test-board-health, test-board-hermes, test-harvest-sweep, test-lint-scattered-ids, test-proof-asset, test-proof-override-order, test-proof-negctl, test-spec-next-pr-scan, test-wrap-deploy, test-wrap-adopt |

These are candidates for `sandbox_known_fail` or for lane-side env (`XDG_CONFIG_HOME`, `UV_CACHE_DIR` under `$TMPDIR`), not for further mktemp work.

## Unsandboxed run

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output: run-all: --changed against 9e86b55d: 283 changed files -> 227 suites (226 named, the rest always-on)
        run-all: all 227 suites passed, 0 skipped for missing tooling   (wall 663s)
```

An earlier `--changed` run at 60b3d583 failed `test-sync-dispatch` and `test-sync-cron-install`: a `TMPDIR` that ends in `/` gives `T//kit.X`, which no longer substring-matches the resolved `/private/var/...` path the scripts print. Both suites now take the canonical path (`pwd -P`); the rerun above is clean.

## Guard test and negative control

```
Command: bash tests/test-mktemp-template-guard.sh
Exit: 0
Output: === 11 passed, 0 failed ===
```

Rules: R1 no mktemp without a template (also `-u`, `-t`); R2 tests never `cd "$(mktemp ...)"`; R3 a test assignment from mktemp carries `|| exit`, `|| return`, `|| die` or `|| VAR=...` on the same line. The test also plants each violation in a fixture and expects it caught, and plants the accepted forms and expects them clean.

```
Command: echo 'NEGCTL_BARE="$(mktemp -d)"' >> tests/test-suite-knob.sh; echo 'cd "$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")"' >> tests/test-suite-knob.sh; bash tests/test-mktemp-template-guard.sh
Exit: 1 (RED expected)
Output: R1 tests/test-suite-knob.sh:30: NEGCTL_BARE="$(mktemp -d)"
        R2 tests/test-suite-knob.sh:31: cd "$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")"
        === 10 passed, 1 failed ===
Restore: git checkout -- tests/test-suite-knob.sh   (committed first)
Exit: 0 (11 passed, 0 failed)
```

## What was not done

- Not run through a real model session: the suite-delta harness in ops-toolkit (`tools/crew/tests/live/suite-delta`) needs one and is a Han-started Mini run. It should run again to get lane numbers.
- The 24 remaining sandbox failures above are not fixed.
- Production code that already used a template (about 100 sites) and code that uses a template under `$HOME/.cache` (gauntlet persist-check) were left as they were.
