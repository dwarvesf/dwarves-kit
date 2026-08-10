# Proof of done: cloud-session support

Change class: behavioral (two hooks, a provisioning engine, two installers).
The proof is the suite, its negative controls, and one observed RED.

## Green run

| Check | Command | Result |
|---|---|---|
| the cloud suite | `bash lib/cloud/tests/smoke.sh` | `smoke: all 79 passed`, exit 0 |
| bin forwarders + census | `bash tests/test-bin-forwarders.sh` | all passed, exit 0 |
| structural integrity | `bash tests/test-meta.sh` | all passed, exit 0 |
| module install matrix | `bash tests/test-install-modules.sh` | 37 passed, 0 failed |
| adopt wiring | `bash tests/test-adopt.sh` | PASS=21 FAIL=0 |
| config registry | `bash tests/test-config-registry.sh` | 19/19 passed |
| kit contract | `bash tests/test-kit-contract.sh` | 23 passed; the 2 remaining offenders are `lib/bench`, red on `origin/master` before this branch |
| shellcheck | `shellcheck -S warning lib/cloud/*.sh hooks/cloud-*.sh bin/cloud lib/cloud/tests/smoke.sh` | clean, exit 0 |
| hook behavior | `bash tests/test-hooks.sh` | 492 / 492, exit 0 |

The full run record, including the real install and adopt flows and both
negative controls, is `docs/verification/cloud-session-support.md`.

## What each invariant is proved by

| Invariant | Assertion in the suite | Negative control |
|---|---|---|
| every path exits 0 | `provision exit code with a broken gh install`, `install-gh exit code with everything broken`, `vm-setup exit code` | the same runs must still print a `!!` line and must NOT print a false `ok  gh` |
| the gate is `CLAUDE_CODE_REMOTE` | `<hook> gates on CLAUDE_CODE_REMOTE`, `<hook> has no '-d $HOME/...' cloud probe` | the grep helper is shown finding a planted old-style probe in a fixture, and reporting absent for a string in no hook |
| the gate really switches behavior | section 2 (OFF: silent, file byte-identical) | section 3 (ON: the same fixture is rewritten). Section 2 alone passes for a permanently broken hook |
| Linux gate at the install point | `install-gh.sh dry-run branch precedes its Linux gate` | section 6e runs both installers behind a `uname` stub answering Darwin and asserts nothing landed in the prefix |
| no `eval` over an environment variable | `provision.sh runs no eval` (comment lines stripped) | a planted `eval echo ~$SUDO_USER` fixture, with an `eval` mention in a comment, is caught once, not twice |
| the dash regex consumes no newline | `line count preserved`, `line 2 is still the blank line`, `line 3 heading byte-for-byte` | `fenced code block untouched`, `inline code span untouched`, `2 dash characters survive in code`, `.ts / .py never opened` |
| `CLAUDE_ENV_FILE` append-once | `CLAUDE_ENV_FILE holds the PATH export` then `append-once across two runs` | a wrong canary prints a `!!` line and no `canary verified` line |
| the consumer-config seam | `rules verb reads [cloud] rules from the project .kit.toml`, `assemble honours [cloud] workspace` | with no project config the kit's own `lib/cloud/CLOUD-RULES.md` is named instead |
| the SessionStart JSON contract | `hookSpecificOutput keys`, `hookEventName is SessionStart`, `reloadSkills is true` | a malformed payload prints `BADJSON` into every field, so the assertions fail rather than skip |
| adopt reaches every tenant repo | `both cloud hooks wired into the tenant settings.json`, `the SessionStart entry keeps the startup\|resume matcher` | a repo adopted without `--with cloud` carries neither hook |

## Observed RED (the suite can go red for the right reason)

The eval lint fired against `provision.sh` on its first run, before comment
stripping, and reported `want: 0 / got: 2`. Both hits were comment lines that
document the retired construct. The lint was narrowed to strip full-line
comments; the planted-eval negative control still reports exactly 1. A test
never seen failing is not a test.

```
FAIL provision.sh contains no eval
  want: 0
  got:  2
```

## Not proved here

| Claim | Status |
|---|---|
| the release-tarball download really works in a cloud VM | UNVERIFIED. The cloud GitHub proxy scopes release-asset requests to the repos attached to the session, so `cli/cli` may answer 403. apt survives as the fallback for exactly this. |
| `cache.agilebits.com` is reachable | UNVERIFIED. It is not on the default network allowlist; the environment owner adds it. Absent it, the op install prints a line and the session continues. |
| the install paths work on Linux | Proved only by the `ubuntu-latest` CI leg. A macOS run stubs `uname`, which proves which BRANCH the code takes, never that the branch works. |
| a plugin installed at SessionStart is usable in the SAME session | PARTIAL. `reloadSkills` is documented to cover skills and commands. Whether a plugin's hooks arm mid-session is not documented; the code claims only the documented part. |
| `drift-check` | NOT PORTED. Four of its five surfaces audit operator curation. Deferred, see SPEC.md Scope. |
