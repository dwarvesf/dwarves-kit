# Proof of done: ship-gate engage verdict no longer flips when a forked bash crashes

The nightly regression run failed `test-ship-gate-command-words` on one case ("global options before stash push"). The suite passes alone and fails at random under load, a different case each time. Cause: Homebrew bash 5 on macOS 27 segfaults in a forked child inside the os_log preferences refresh, and a parent that hit it keeps crashing its children. The hook builds its engage views through pipelines and falls back to the unblanked command when one dies, so the verdict flipped (a quoted-separator push skipped the gate, or a stash push was blocked as "the command parser gave no answer"). The fix exports `OS_ACTIVITY_MODE=disable` at the top of `hooks/ship-gate.sh`. The nightly job sets `PATH` with `/opt/homebrew/bin` first, so it runs Homebrew bash; the hook configs also call `bash` by name, so the gate itself was exposed.

## Root cause evidence

Command: `bash -x` trace of the unfixed hook on `git -C "a;b" push -u origin HEAD` (4 workers, nightly `PATH`), then a patched copy that logs `PIPESTATUS` of the `CMD_ENG` pipeline
Exit: 0
Output:
```
+ CMD_ENG='git -C "___" push -u origin HEAD'     <- the blanked copy was built
+ CMD_ENG='git -C "a;b" push -u origin HEAD'     <- then the || fallback overwrote it
+ exit 0                                         <- no engage: the gate let the push through

PS=0 0 0      151 invocations
PS=0 0 139      9 invocations   (third stage, a bash function that runs sed, died with SIGSEGV)
```
Verdict: PASS

Command: read the crash reports macOS wrote for bash on this host (`~/Library/Logs/DiagnosticReports/bash-2026-11-09-040714.000.ips` is inside the nightly window; `bash-2026-11-09-081534.ips` is from the probe)
Exit: 0
Output:
```
procPath /opt/homebrew/*/bash   exception EXC_BAD_ACCESS / SIGSEGV   macOS 27.0.1
frame 0  libsystem_trace.dylib  _os_log_preferences_refresh
frame 1  libsystem_trace.dylib  os_log_type_enabled
frame 2  CoreFoundation         -[CFPrefsSearchListSource alreadylocked_copyValueForKey:]
```
Verdict: PASS

## Failure rate before and after

The harness feeds real PreToolUse payloads to the hook in a repo with the gate on, four workers at once, `env -i` with the nightly `PATH` and the per-user `TMPDIR`. The push word is built at runtime so the session's own gate does not read the script.

Command: `bash flake-probe.sh` on the unfixed hook, engaging command `git -C "a;b" push -u origin HEAD`, 160 runs
Exit: 0
Output:
```
 152 rc=2   (engaged, correct)
   8 rc=0   (gate skipped, wrong)
```
Verdict: PASS (flake reproduced)

Command: same probe on the fixed hook, 2 inert workers (`git stash push -m x`) and 2 engaging workers, 40 runs each, repeated twice
Exit: 0
Output:
```
 80 engage rc=2      80 inert rc=0
 80 engage rc=2      80 inert rc=0
```
Verdict: PASS (0 wrong of 320; with `OS_ACTIVITY_MODE=disable` set from outside the hook instead, 0 wrong of 160, so the in-hook export reaches the same effect)

A retry around each capture was tried first and did not help: once a parent process starts crashing its children, all three attempts die. It was removed.

## Suite results

Command: `bash tests/test-ship-gate-command-words.sh` on the unfixed hook, 4 copies at once in the nightly environment
Exit: 1
Output:
```
run1: NOT ok - quoted ; in the -C dir ; NOT ok - stash push with ${IFS}   PASS=131 FAIL=2
run2: NOT ok - quoted ; in the -C dir                                      PASS=132 FAIL=1
run3: PASS=133 FAIL=0
run4: NOT ok - quoted ; inside a substitution                              PASS=132 FAIL=1
```
Verdict: PASS (red reproduced)

Command: `bash tests/test-ship-gate-command-words.sh`
Exit: 0
Output:
```
ok - hook children run with os_log silenced
---
PASS=134 FAIL=0
```
Verdict: PASS

Command: the same suite, 4 copies at once in the nightly environment, run twice
Exit: 0
Output:
```
verify-conc2: run1..run4  PASS=134 FAIL=0 (all four)
verify-conc3: run1..run4  PASS=134 FAIL=0 (all four)
```
Verdict: PASS

Command: every `tests/test-*.sh` that names `hooks/ship-gate.sh` (the command-words, coverage-map, default-push, fail-closed, identities, impl-notes, profiles, refs-block and review-verdict suites among them)
Exit: 0
Output:
```
all ok; test-ship-gate-review-verdict failed once while a negative control was swapping hooks/ship-gate.sh underneath it
(bash reads a script as it runs, so a swapped file garbles the run); rerun alone three times: pass=60 fail=0 each
```
Verdict: PASS

Command: `bash lib/codex/repin.sh && bash lib/codex/repin.sh check && bash tests/test-codex-hooks.sh`
Exit: 0
Output:
```
repin: repinned hooks/ship-gate.sh
repin: all pins fresh in hooks/codex-hooks.json
94 passed, 0 failed
```
Verdict: PASS (the content-hash pin of the edited hook is rewritten; `repin.sh check` exited 1 before)

Command: `bash tests/run-all.sh --changed`
Exit: 0
Output:
```
run-all: all 32 suites passed, 0 skipped for missing tooling
```
Verdict: PASS

## Negative control

Command: `bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-command-words.sh" "git show origin/master:hooks/ship-gate.sh >| hooks/ship-gate.sh"`
Exit: 0
Output:
```
Mutation: git show origin/master:hooks/ship-gate.sh >| hooks/ship-gate.sh
Changed: hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)
Output:
  NOT ok - hook children should see OS_ACTIVITY_MODE=disable (saw: unset )
  ---
  PASS=133 FAIL=1

Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```
Verdict: PASS (RED on the master hook, green after restore)

## Class fix, not a one-off

Every pipeline in the hook is exposed to the same crash, not only the two that failed here. Setting the switch once at the top covers all of them. The new test checks the environment a child sees, so it is deterministic. The random crash itself cannot be forced, so the failure-rate probe above is the evidence that it is gone.
