# Proof of done: ship-gate engage verdict no longer flips when a forked bash crashes

The nightly regression run failed `test-ship-gate-command-words` on one case ("global options before stash push"). The suite passes alone and fails at random under load, a different case each time. Cause: Homebrew bash 5 on macOS 27 segfaults in a forked child inside the os_log preferences refresh (`libintl_setlocale` under `dispose_temporary_env` under `command_substitute`, fired by the `LC_ALL=C sed` temp-env prefixes). The hook builds its engage views through pipelines and used to fall back to the unblanked command, or to nothing, when one died, so the gate failed OPEN: a quoted-separator push, a `${IFS}` push or a `gh pr create` skipped it. The nightly runs with `/opt/homebrew/bin` first on `PATH`, and the hook configs also call `bash` by name, so the gate itself was exposed.

Three changes, all in `hooks/ship-gate.sh`:

- Guard: a capture (`CMD_CODE`, `CMD_IFS`, `CMD_GH`, `CMD_GIT`, `CMD_ENG`) that fails or comes back empty from non-empty input sets `CAP_FAIL`; the engage check then engages whenever the raw command looks like a push or a `gh pr create`, by bash's own regex (no fork). The engage greps read here-strings instead of `< <(echo ..)`. `_hit` runs the same regex in bash itself when grep errors, so a dead grep never reads as "no match"; the heredoc-to-shell check goes through it. The parser-output scan (`@@DEFAULT-PUSH`, `@@FORCE`, `@@DEFAULT`, `@@BLOCK`, `@@REF`) is one pure-bash loop, so a dead grep can neither hide a push to the default branch nor leave the pushed branch unresolved. The `${IFS..}` fallback replaces the matched text literally, so `${IFS[*]}`, `${IFS[0]}` and `${IFS#?}` are read as spaces too.
- Trigger: `LC_ALL=C sed` becomes `env LC_ALL=C sed`, so bash never resets its own locale in the forked child.
- Belt and braces: `export OS_ACTIVITY_MODE=disable` at the top.

`hooks/codex-hooks.json` carries the repinned content hash of the hook.

## Root cause evidence

Command: `bash -x` trace of the original hook on `git -C "a;b" push -u origin HEAD` (4 workers, nightly `PATH`), then a patched copy that logs `PIPESTATUS` of the `CMD_ENG` pipeline
Exit: 0
Output:
```
+ CMD_ENG='git -C "___" push -u origin HEAD'     <- the blanked copy was built
+ CMD_ENG='git -C "a;b" push -u origin HEAD'     <- then the || fallback overwrote it
+ exit 0                                         <- no engage: the gate let the push through

PS=0 0 0      151 invocations
PS=0 0 139      9 invocations   (third stage died with SIGSEGV)
```
Verdict: PASS

Command: read the crash reports macOS wrote for bash on this host (`~/Library/Logs/DiagnosticReports/bash-2026-11-09-040714.000.ips` is inside the nightly window)
Exit: 0
Output:
```
procPath /opt/homebrew/*/bash   exception EXC_BAD_ACCESS / SIGSEGV   macOS 27.0.1
frame 0  libsystem_trace.dylib  _os_log_preferences_refresh
frame 1  libsystem_trace.dylib  os_log_type_enabled
frame 2  CoreFoundation         -[CFPrefsSearchListSource alreadylocked_copyValueForKey:]
```
Verdict: PASS

An env switch alone was tried first and a retry around each capture was tried before that. The retry does not help: once a parent starts crashing its children, all three attempts die. The env switch cut the failure rate but left the fail-open fallbacks in place, hence the guard.

## Failure rate before and after

The harness feeds real PreToolUse payloads to the hook in a repo with the gate on, four workers at once, `env -i` with the nightly `PATH` and the per-user `TMPDIR`. The push word is built at runtime so the session's own gate does not read the script.

Command: probe on the original hook, engaging command `git -C "a;b" push -u origin HEAD`, 160 runs
Exit: 0
Output:
```
 152 rc=2   (engaged, correct)
   8 rc=0   (gate skipped, wrong)
```
Verdict: PASS (flake reproduced)

Command: probe on the final hook, 2 inert workers (`git stash push -m x`, `git${IFS}stash${IFS}push`) and 2 engaging workers (`git -C "a;b" push -u origin HEAD`, `git${IFS[*]}push${IFS[*]}origin${IFS[*]}HEAD`), 40 runs each, 2 rounds. An earlier run of this probe had a typo in the inert commands (`puush`), so it proved less than it claimed; this is the corrected run.
Exit: 0
Output:
```
 160 engage right
 160 inert right
```
Verdict: PASS (0 wrong verdicts of 320)

## Suite results

Command: `bash tests/test-ship-gate-command-words.sh`, original hook, 4 copies at once in the nightly environment
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
ok - dead capture: ${IFS} push (ifs view) -> engaged
ok - dead capture: quoted ; in the -C dir (views) -> engaged
ok - dead capture: quoted ; inside backticks -> engaged
ok - dead capture: gh pr create (gh view) -> engaged
ok - dead capture: gh pr new after cd (gh view) -> engaged
ok - dead capture: ${IFS[*]} push (ifs view, glob form) -> engaged
ok - dead capture: ${IFS[0]} push (ifs view, index form) -> engaged
ok - dead capture: heredoc to bash holding a push (shell check) -> engaged
ok - dead capture: single-branch push (@@REF scan) -> engaged
ok - dead capture: push to main still refused
---
PASS=145 FAIL=0
```
Verdict: PASS

The dead-capture cases put shims for `sed`, `awk` and `grep` first on `PATH`. Each exits 139 with no output when it is the tool that builds one view of the command, and runs the real tool otherwise. The hook has to engage anyway.

Command: the same suite under system bash 3.2 (`env -i PATH=/usr/bin:/bin:/usr/sbin bash tests/test-ship-gate-command-words.sh`), and 4 copies at once in the nightly environment
Exit: 0
Output:
```
bash 3.2.57: PASS=145 FAIL=0
4 concurrent, nightly env: run1..run4  PASS=145 FAIL=0 (all four)
```
Verdict: PASS

Command: every `tests/test-*.sh` that names `hooks/ship-gate.sh`, then `bash tests/test-proof-negctl.sh` on a clean tree
Exit: 0
Output:
```
all ok (command-words, coverage-map, default-push, fail-closed, identities, impl-notes, profiles, refs-block, review-verdict, ...)
test-proof-negctl: all 57 passed   (it reports FAIL while the tree holds uncommitted edits; commit first)
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
Verdict: PASS (`repin.sh check` exited 1 before the repin)

Command: `bash tests/run-all.sh --changed`
Exit: 0
Output:
```
run-all: all 32 suites passed, 0 skipped for missing tooling
```
Verdict: PASS (run on the first revision of this branch)

## Negative control

Command: `bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-command-words.sh" "git show HEAD~1:hooks/ship-gate.sh >| hooks/ship-gate.sh"` (the hook as of the previous review round)
Exit: 0
Output:
```
Exit: 1 (under mutation, RED expected)
  NOT ok - dead capture: ${IFS[*]} push (ifs view, glob form) -> should engage (exit 2)
  NOT ok - dead capture: ${IFS[0]} push (ifs view, index form) -> should engage (exit 2)
  NOT ok - dead capture: heredoc to bash holding a push (shell check) -> should engage (exit 2)
  NOT ok - dead capture: single-branch push (@@REF scan) -> should engage (exit 2)
  PASS=141 FAIL=4
Exit: 0 (green after restore)
```
Verdict: PASS (RED on the previous branch head, green after restore)

Command: `bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-command-words.sh" "git show origin/master:hooks/ship-gate.sh >| hooks/ship-gate.sh"`
Exit: 0
Output:
```
Exit: 1 (under mutation, RED expected)
  NOT ok - hook children should see OS_ACTIVITY_MODE=disable
  NOT ok - nine of the ten dead-capture cases (all but push-to-main)
  PASS=135 FAIL=10
Exit: 0 (green after restore)
```
Verdict: PASS (RED on the master hook, green after restore)

Earlier round: against the env-switch-only hook six dead-capture cases were red (134/6).

## Not covered (named follow-up)

Later gates in the hook still read command output through `< <(..)` or pipelines that a dead child could empty: the cd/-C directory extraction near the top of the repo resolution, the BACKLOG slug check, the default-branch and FEATURES diff checks, the hooks-dir archive check, the ledger greps, and the `jq` and `awk` calls that parse the payload. They run after the engage and push-to-default decisions, so a dead child there can skip a later gate (a spec, ledger or registry check) but not the push-to-default block. They need the same here-string and pure-bash treatment in a follow-up.
