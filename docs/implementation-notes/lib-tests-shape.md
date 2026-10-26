# Implementation note: lib-tests-shape

No spec backs this change. This note records the decisions and the findings a reader cannot get from the diff.

## What was wrong

- `tests/run-all.sh` and `bin/test-affected` collected `tests/test-*.sh` only. The suites under `lib/<m>/tests/` ran in no runner, no CI job and no hook. The audit that started this change counted fewer. It missed the `smoke.sh` suites and most of the stats and skill-curator groups.
- `tests/test-queue.bats` matched no glob. bats is installed on the maintainer's machine and nowhere in CI, so the queue launcher's cases never ran there.
- `lib/<m>/` had 21 modules without a README.

## Decisions

- **One definition, fallback-safe.** `tests/lib/suites.sh` defines `suite_list`, `is_suite`, `suite_id`, `suite_path` and `suite_owner`. `run-all.sh` sources it as a hard dependency, like `job-count.sh`, and the five run-all fixture suites now copy it. `bin/test-affected` keeps a built-in `tests/test-*.sh` fallback when the file is absent, as it already does for `timeout.sh`, so its many throwaway fixture repos need no change.
- **Suite ids are path-derived.** A bare basename collides: `test-docs-wiring` exists under `tests/` and under `lib/stats/tests/`. A module suite goes by `lib-<module>-<name>` (`lib-stats-test-docs-wiring`). The id keys the report line, `bin/test-affected.timeouts`, the timing history and `--failed`. `tests/run-all.sh --only` matches the id.
- **What counts as a module suite.** `test-*.sh` and `smoke.sh` directly under `lib/<m>/tests/` or `lib/<m>/<sub>/tests/`. Fixtures and `tests/lib` helpers are not suites.
- **`--changed` mapping.** A changed path under `lib/<m>/` picks every suite under that module, sub-tool suites included (`lib/session/audit/x` picks the `lib/session/observe` suites). Over-picking is the stated policy of the runner. The reason prints as `module lib/<m>`. A changed module suite picks itself. The older rule that picks `tests/test-<m>*.sh` is unchanged.
- **Python tests stay wrapped.** `bench`, `sync` and `webcheck` already had a root entry. `lib/session/recall` did not. So `tests/test-session-recall.sh` runs its unittest file the way `tests/test-bench.sh` does. A guard in `tests/test-suites-collect.sh` fails when a `test_*.py` under `lib/` has no root entry.
- **bats port.** The file used only `run`, `$status` and `$output`. The port keeps every case body byte for byte and adds a small harness at the top of `tests/test-queue.sh`: one subshell per case, `set -e`, an ERR trap that names the failing line, and a `run` helper. `tests/test-queue.bats` is removed because two copies would drift. A mutation of one assertion turned exactly that case red.
- **A trap inside the harness.** Wrapping the case subshell in `|| rc=$?` made bash skip its ERR trap, so failures printed no line. The harness reads `$?` on the next line instead. A comment in the file says why.
- **Ceilings.** Every new suite has a line in `bin/test-affected.timeouts`. Most take the 60 s floor. The stats suites run `uv run` on every step and went over 60 s once on a cold environment under load 50 (one timed out, one took 126 s). Those carry hand-set 120 s and 180 s lines with a reason. The header allows that for `test-wrap-land`.
- **`requires: uv`.** The stats suites declare it, so a host without uv skips them with a reason instead of failing. CI installs uv, so they run there.

## Findings from the first runs

- `lib/stats/tests/test-schema-conform.sh` died with exit 141 on the maintainer's machine: `grep -m1` over many live ledgers plus `head -1` under `pipefail` is a SIGPIPE. With no live ledger it would exit 2. Fixed with `|| true`. The fixture-line fallback below it was already there.
- `lib/session/observe/tests/test-vps-report.sh` called `SourceFileLoader.load_module()`, which newer Pythons removed. It failed only under Python 3.15. Replaced with `module_from_spec` and `exec_module`.
- Everything else was green on first run, alone and in parallel, with a fake `HOME`, no `claude` and a cold uv cache.

## Left as found

- `tests/test-codex-hooks.sh` is red on `origin/master`: the pin for `hooks/commit-format.sh` is stale. `bash lib/codex/repin.sh` fixes it. It is outside this change, and it shows in `run-all --changed` only because the diff touches `tests/`.
- `tests/lib/test-affected-replay.sh` lists suites with `ls tests/test-*.sh`. It is an independent oracle for `bin/test-affected`, so it was not changed to share the new helper. It does not yet replay module-suite picks.
- `lib/stats/tests/test-schema-conform.sh` still reads the operator's live ledger when one exists. It passes either way.

## Module READMEs

Twenty-one modules gained a README written from the code: entry points, `bin/` forwarders, test homes, spec or docs. `lib/README.md` links every module row to its README. No spec file moved or was renamed.

## ubuntu 26.04 round

CI run 40370883570 on this branch: macOS green, three newly wired module suites red on ubuntu 26.04. They never ran on Linux before; the wiring exposed them.

| Suite | Cause | Fix |
|---|---|---|
| lib-session-test-handoffs | `lib/session/handoffs.sh` read the mtime with `stat -f '%m' \|\| stat -c '%Y'`. On GNU stat `-f` is a filesystem query: it exits 0 and prints several lines, so the fallback never ran and the age arithmetic failed under `set -e`. Every listing printed nothing; only the empty-repo and usage cases passed. | `stat -c %Y` first, digits only, then `stat -f %m`, then now. `\|\| true` on each, because the script runs under `set -e`. |
| lib-skill-curator-test-curate | `lib/skill-curator/lib/curate.sh` had the same BSD-first chain. The garbage mtime went into `jq --argjson mt`, giving an empty inventory and "invalid JSON text". | Same shape, default 0. |
| lib-stats-test-memory-lens | The "PermissionError path is skipped" fixture named `/var/root/...`, unreadable on macOS only. On Linux it is absent, so `exists()` is False and the note read as dead. The product is right; the fixture assumed macOS. | The fixture makes its own `chmod 000` directory under the temp root. As root the assertion is skipped with a printed line, since root ignores chmod. The dir is made removable again at the end. |

One trap while fixing: the first version of the handoffs fix dropped the `||` chain and exited silently on macOS, because `stat -c` fails there and `set -e` ended the script. The test caught it. Both fixes carry `|| true`.

Other BSD-first `stat -f` chains: none remain in `lib/`. The rest already try `stat -c` first (`wrap-common.sh`, `queue.sh`, `orchestrate.sh`, `hook-util.sh`, `spec-next.sh`, `work.sh`).

Verification: all three pass in an `ubuntu:26.04` container (non-root user, uutils coreutils) and on macOS; `run-all.sh --only lib-` passes 38 of 38 there. The three fail in the same container before the fix. Proof: `docs/verification/lib-tests-shape.md`, section "ubuntu 26.04 failures".
