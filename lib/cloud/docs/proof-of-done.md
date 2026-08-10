# Proof of done: cloud-session support

Change class: behavioral (two hooks, a provisioning engine, two installers).
The proof is the suite, its negative controls, and two observed REDs.

Pinned to commit `f1612c0`. The full run record, including the real install and
adopt flows and every negative control, is
`docs/verification/cloud-session-support.md`.

## Green run

| Check | Command | Result |
|---|---|---|
| the cloud suite | `bash lib/cloud/tests/smoke.sh` | `smoke: all 118 passed`, exit 0 |
| hook behavior | `bash tests/test-hooks.sh` | 492 / 492, exit 0 |
| structural integrity | `bash tests/test-meta.sh` | 799 / 799, exit 0 |
| bin forwarders + census | `bash tests/test-bin-forwarders.sh` | 33 passed, exit 0 |
| module install matrix | `bash tests/test-install-modules.sh` | 37 passed, 0 failed |
| adopt wiring | `bash tests/test-adopt.sh` | PASS=21 FAIL=0 |
| config registry | `bash tests/test-config-registry.sh` | 19/19 passed |
| kit contract | `bash tests/test-kit-contract.sh` | 23 passed; the 2 offenders are `lib/bench`, red on `origin/master` before this branch |
| shellcheck | `shellcheck -S warning lib/cloud/*.sh lib/cloud/tests/smoke.sh hooks/cloud-*.sh bin/cloud` | clean, exit 0 |

## What each invariant is proved by

| Invariant | Assertion in the suite | Negative control |
|---|---|---|
| every path exits 0 | `provision exit code with a broken gh install`, `install-gh exit code with everything broken`, `vm-setup exit code`, `assemble exits 0 with every step exercised` | the same runs must still print a `!!` line and must NOT print a false `ok  gh`; a run with nothing failing must reach `CLOUD-READY` |
| the gate is `CLAUDE_CODE_REMOTE` | `<hook> gates on CLAUDE_CODE_REMOTE`, `<hook> has no '-d $HOME/...' cloud probe` | the same pattern is shown firing on a fixture byte-identical to the historical gate shape |
| the gate really switches behavior | section 2 (OFF: silent, file byte-identical) | section 3 (ON: the same fixture is rewritten). Section 2 alone passes for a permanently broken hook |
| each hook needs its own switch | `<hook> checks <SWITCH>`, `<hook> checks the switch before CLAUDE_CODE_REMOTE`, and the no-switch runs leave the file byte-identical | the order check is shown reporting `no` on a fixture whose switch comes second |
| Linux gate at the install point | `install-gh.sh dry-run branch precedes its Linux gate` | section 6e runs both installers behind a `uname` stub answering Darwin and asserts nothing landed in the prefix |
| no `eval` over an environment variable | `provision.sh runs no eval` (comment lines stripped) | a planted `eval echo ~$SUDO_USER` fixture, with an `eval` mention in a comment, is caught once, not twice |
| the dash regex consumes no newline | `line count preserved`, `line 2 is still the blank line`, `line 3 heading byte-for-byte` | `fenced code block untouched`, `inline code span untouched`, `2 dash characters survive in code`, `.ts / .py never opened` |
| unbalanced fences skip the file whole | `a file with unbalanced fences is skipped whole` | the same content with the fence CLOSED IS rewritten, so the row above is the fence rule and not a guard that never writes |
| `CLAUDE_ENV_FILE` append-once | `CLAUDE_ENV_FILE holds the PATH export` then `append-once across two runs` | a wrong canary prints a `!!` line and no `canary verified` line |
| the consumer-config seam | `rules verb reads [cloud] rules from the project .kit.toml`, `assemble honours [cloud] workspace`, `CLOUD_<KEY> beats a conflicting project value` | with no project config the kit's own `lib/cloud/CLOUD-RULES.md` is named instead |
| a `~` in a config value expands | `a ~ workspace lands in HOME` | no literal `~` directory was created under the repo |
| the operator tier holds | 5 assertions that a hostile `.kit.toml` reaches neither the plugin installer, the hooks arming, the secrets step, nor the sibling clone | the same keys DO take effect from the operator tier, and a PROJECT-tier key from the same hostile file is still honoured |
| the tier split cannot drift | `every [cloud] key is declared in exactly one tier and read through it` | the extraction is asserted non-empty, so the check cannot pass vacuously |
| the assemble pipeline's supporting steps | 9 assertions over one run: background layer (memory count, AGENTS.md, CLAUDE.md), toolchain report, hooks arming, board smoke, sibling-clone failure, plugin no-op | a run with nothing failing reaches `CLOUD-READY`, so the `CLOUD-PARTIAL` row is not a provision that always fails |
| the SessionStart JSON contract | `hookSpecificOutput keys`, `hookEventName is SessionStart`, `reloadSkills is true` | a malformed payload prints `BADJSON` into every field, so the assertions fail rather than skip |
| adopt reaches every tenant repo | `both cloud hooks wired into the tenant settings.json`, `the SessionStart entry keeps the startup\|resume matcher` | a repo adopted without `--with cloud` carries neither hook |
| the suite goes red | section 9 re-invokes the suite with one planted failure and asserts exit 1 | the same re-invocation with nothing planted exits 0 |

## Observed RED (the suite can go red for the right reason)

First, the eval lint fired against `provision.sh` before comment stripping was
added, reporting `want: 0 / got: 2`. Both hits were comment lines documenting
the retired construct. The lint was narrowed to strip full-line comments; the
planted-eval negative control still reports exactly 1.

```
FAIL provision.sh contains no eval
  want: 0
  got:  2
```

Second, the board smoke assertion fired against a verb that does not exist. The
ported call was `board render <file>`; the real interface is
`board board --backlog-file <file>`, and `bin/board` answers
`--backlog-file is required for single-repo commands`. The ported code and the
ported rules table both carried the wrong form, and nothing had ever run it.

```
FAIL board smoke ran against the repo's kanban
  want: yes
  got:  no
```

A test never seen failing is not a test.

## Not proved here

See the "Not covered here" table in `docs/verification/cloud-session-support.md`
for the full list, including the two installs that only a real cloud VM can
prove and the CI leg that has not been dispatched.
