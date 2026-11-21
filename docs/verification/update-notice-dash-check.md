# Verification -- update-notice-dash-check

The nightly regression went red on one suite, `test-update-check-notice`: `line 32: [: : integer expected` and a FAIL on "the hook and this test have no em or en dash". The hook has no dash. The cause is a bash crash, not a dash: the check ran `$(! LC_ALL=C grep -q ... ; echo $?)`, and in about 8 percent of runs under the nightly's env (`env -i`, PATH with /opt/homebrew/bin first, so Homebrew bash 5.3.20) the substitution subshell dies with SIGSEGV (status 139) the moment it applies the `LC_ALL=C` prefix. The substitution is then empty, and `[ "" -eq 0 ]` is the bash error. The line has been in the suite since the notice hook landed, so the failure is a latent flake, not a regression from the latest merge; about one run in twelve, so a run of green nights does not clear it. Apple /bin/bash 3.2 never crashed in 240 runs.

| # | Run | Command | Result | Verdict |
|---|---|---|---|---|
| 1 | Green, fixed suite | `bash tests/test-update-check-notice.sh` | exit 0, `37 passed, 0 failed` | PASS |
| 2 | Flake rate, fixed suite | 40 rounds of 6 parallel runs under the nightly env | runs=240 failed=0 bash_integer_error=0 | PASS |
| 3 | Negative control: the old line | same loop on origin/master | runs=240 failed=19 bash_integer_error=19 | PASS |
| 4 | Same loop, old line, Apple bash 3.2 | same loop with `/bin/bash` | runs=240 failed=0 | PASS (version-specific crash) |
| 5 | Dash check still bites | fixed test, an en dash appended to a copy of the hook | exit 1, `FAIL the hook and this test have no em or en dash` | PASS |
| 6 | Empty status is a FAIL | `check "empty status" ""` | prints FAIL, no bash error | PASS |
| 7 | Personal-path scan | `bash tests/test-no-personal-paths.sh` | exit 0 | PASS |

## Green run
```
Command: bash tests/test-update-check-notice.sh
Exit: 0
Output (tail):
  PASS  settings.json: one SessionStart entry, matcher startup, timeout 5 (got: startup|5)
  PASS  the hook and this test have no em or en dash

== 37 passed, 0 failed ==
```

```
Command: loop of 40 rounds x 6 parallel: env -i HOME=$HOME PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" bash tests/test-update-check-notice.sh
Exit: 0 (the loop)
Output: runs=240 failed=0 bash_integer_error=0
```

## NEGATIVE CONTROL
The original line, on a clean clone of origin/master (4db54a0), same loop:
```
Command: loop of 40 rounds x 6 parallel: env -i HOME=$HOME PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" bash tests/test-update-check-notice.sh
Exit: 0 (the loop; each failing run exited 1)
Output: runs=240 failed=19 bash_integer_error=19
```
Every failure is the same two lines: `line 32: [: : integer expected` and the dash FAIL. A probe that kept each substitution's status showed `st=139` (SIGSEGV) for `$(! LC_ALL=C grep ...)`, and an empty result for `$(LC_ALL=C true; echo $?)` in the same failing process, so any `LC_ALL=C <cmd>` prefix inside a substitution is affected there. `export LC_ALL=C` inside the substitution, and `env LC_ALL=C grep`, survived in those same processes.

## What changed
- The dash check exports `LC_ALL=C` inside the substitution instead of prefixing the grep.
- `check()` passes only on a literal `0`. An empty or non-numeric status is a FAIL line, never a bash error, and never a pass.

## Not changed
Other files under tests, lib, hooks and bin use an `LC_ALL=C <cmd>` prefix (census: `rg -n 'LC_ALL=C [a-z/]' tests lib hooks bin`). None failed in the nightly run; the crash needs Homebrew bash 5.3.20 and was only measured here in this one suite. A prefix inside a command substitution in a live hook would return empty under the same bash; that is not verified and not touched.
