# Proof of done: ci-env-tests (bug lane, 2026-06-10)

Defect: master CI red on both matrix platforms since the quality wave merged (every push
from PR #45 onward, first failing run 27284452444). Two independent platform-portability
bugs, one per runner. Root cause was recorded in the debug ledger BEFORE any fix
(`.claude/debug/ci-env-tests.md`, session-local: `.claude/` is gitignored, so the
load-bearing content is mirrored here).

## Root cause

1. **macOS runner, `stack-merge: zero-arg chain` expected 64 got 1.** bash 3.2 (`/bin/bash`
   on stock macOS and macOS runners) aborts on `set -u` + empty-array expansion
   (`args[@]: unbound variable`, exit 1) before the usage check can return 64; bash 4.4+
   allows it. Dev Macs resolve `bash` to brew bash 5.x, hence "passes locally".
2. **ubuntu runner, `colors: PTY progress emits escape bytes` false.** The test used the
   BSD form `script -q /dev/null bash -c "<cmd>"`; util-linux `script` takes only the
   typescript file positionally and errors `unexpected number of arguments` (stderr
   swallowed by `2>/dev/null`), so zero escape bytes were counted.

Eliminated en route: "PR #49 broke CI" (master itself red before #49's run; #49 is
doc-only) and "flaky PTY timing" (both failures deterministic, reproduced outside CI on
first try). Same-class sweep: all other `[@]` expansions in lib/ + hooks/ are
count-guarded or static; only stack-merge.sh was exposed.

## Fix

- `lib/goal/stack-merge.sh` main() dispatch: `${args[@]+"${args[@]}"}` guard on `next` and `chain` (4425f4d).
- `tests/test-hooks.sh` colors test: detect script(1) flavor via `script --version | grep util-linux`, use `script -qec "<cmd>" /dev/null` on util-linux, BSD positional form otherwise (568cb58).

## Green run

Command: `/bin/bash lib/goal/stack-merge.sh chain --dry-run` (bash 3.2.57, the failing interpreter)
Exit: 64, output `usage: chain <pr#> [<pr#>...] [--dry-run]`

Command: `/bin/bash tests/test-hooks.sh` (full suite under 3.2, macOS CI parity)
Exit: 0, output (tail): `Passed: 316 / 316`

Command: full suite in ubuntu:24.04 container (util-linux 2.39.3, ubuntu CI parity)
Output: `PASS colors: PTY progress emits escape bytes`, `PASS colors: piped progress emits ZERO escape bytes`

Command: `bash tests/test-meta.sh`
Exit: 0, output (tail): `Passed: 426 / 426`

CI (the real acceptance seam, run 27286820530 on PR #51):
test (macos-latest) pass 30s; test (ubuntu-latest) pass 25s.

## NEGATIVE CONTROL (revert -> RED -> restore -> GREEN)

Run 2026-06-10 after the green run, on the fix branch:

1. `git checkout HEAD~2 -- lib/goal/stack-merge.sh tests/test-hooks.sh` then
   `/bin/bash lib/goal/stack-merge.sh chain --dry-run` -> `line 85: args[@]: unbound variable`, exit 1 (RED).
   Restore (`git checkout HEAD -- ...`) -> exit 64 with usage (GREEN).
2. `git checkout HEAD~1 -- tests/test-hooks.sh` then suite in ubuntu:24.04 container ->
   `FAIL colors: PTY progress emits escape bytes (condition false)` (RED).
   Restore -> `PASS colors: PTY progress emits escape bytes` (GREEN).

## Reproduce

- RED side, bug 1: check out 0469c65 (or revert 4425f4d) and run `/bin/bash lib/goal/stack-merge.sh chain --dry-run` on any macOS box; expect exit 1.
- RED side, bug 2: revert 568cb58 and run `bash tests/test-hooks.sh` on any util-linux distro; expect the PTY colors FAIL.
- GREEN side: this branch; CI run 27286820530.

## Telemetry

Escaped-defect markers recorded against the owning specs for retro aggregation:
`gate-ledger.sh action ci-env-tests "escaped-from=stack-merge"` and `"escaped-from=quality-followups"`.
