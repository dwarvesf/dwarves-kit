# Proof of done: cloud-session support

Change class: behavioral (two hooks, a provisioning engine, two installers).
The proof is the suite, its negative controls, and the observed REDs.

Pinned to commit `547076e`. The full run record, including the real install and
adopt flows and every negative control, is
`docs/verification/cloud-session-support.md`. The adversarial-review round that
followed the first pin is the dated section at the bottom of this file; the
counts below are the post-review ones.

## Green run

| Check | Command | Result |
|---|---|---|
| the cloud suite | `bash lib/cloud/tests/smoke.sh` | `smoke: all 146 passed`, exit 0 |
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
| the gate really switches behavior, and WHICH gate | sections 2 and 3 (OFF silent and byte-identical, ON rewritten) plus the Darwin-stub block at the end of section 3 | neutering any ONE of the three gates turns the suite red: the switch, `CLAUDE_CODE_REMOTE`, and Linux each have their own run. Recorded below |
| each hook needs its own switch | `<hook> checks <SWITCH>`, `<hook> checks the switch before CLAUDE_CODE_REMOTE`, and the no-switch runs leave the file byte-identical | the order check is shown reporting `no` on a fixture whose switch comes second |
| Linux gate at the install point | `install-gh.sh dry-run branch precedes its Linux gate` | section 6e runs both installers behind a `uname` stub answering Darwin and asserts nothing landed in the prefix |
| no `eval` over an environment variable | `provision.sh runs no eval` (comment lines stripped) | a planted `eval echo ~$SUDO_USER` fixture, with an `eval` mention in a comment, is caught once, not twice |
| the dash regex consumes no newline | `line count preserved`, `line 2 is still the blank line`, `line 3 heading byte-for-byte` | `fenced code block untouched`, `inline code span untouched`, `2 dash characters survive in code`, `.ts / .py never opened` |
| unbalanced fences skip the file whole | `a file with unbalanced fences is skipped whole` | the same content with the fence CLOSED IS rewritten, so the row above is the fence rule and not a guard that never writes |
| `CLAUDE_ENV_FILE` append-once | `CLAUDE_ENV_FILE holds the PATH export` then `append-once across two runs` | a wrong canary prints a `!!` line and no `canary verified` line |
| the consumer-config seam | `rules verb reads [cloud] rules from the project .kit.toml`, `assemble honours [cloud] workspace`, `CLOUD_<KEY> beats a conflicting project value` | with no project config the kit's own `lib/cloud/CLOUD-RULES.md` is named instead |
| a `~` in a config value expands | `a ~ workspace lands in HOME` | no literal `~` directory was created under the repo |
| the operator tier holds | 6 assertions that a hostile `.kit.toml` reaches neither the plugin installer, the hooks arming, the secrets step, the sibling clone, nor the workspace choice | the same keys DO take effect from the operator tier, and `rules`, a real PROJECT-tier key naming a real in-repo path in the SAME hostile file, is still honoured |
| the tier split is internally consistent | `every [cloud] key is declared in exactly one tier and read through it` | the extraction is asserted non-empty, so the check cannot pass vacuously. This is a CONSISTENCY check only: it cannot tell whether a key sits in the right list, and three keys that reached outside the repo passed it |
| a project-tier PATH stays inside the repo | section 5b-3: for both `map` and `rules`, an absolute path, a `..` traversal and a committed symlink out of the repo are each refused with a `!!` line | the legitimate repo-relative use of both keys is still printed |
| `op_version` cannot shape the download URL | section 5b-3: a project `.kit.toml` value never reaches the URL, and a traversal-shaped value is refused at the operator tier too | the operator tier DOES set a real pin, and the URL carries it |
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

## 2026-08-11 adversarial review round (commit `547076e`)

An adversarial review demonstrated each finding live rather than describing it.
One finding is that the previous version of THIS file was wrong: it claimed the
gate "really switches behavior" and the suite did not prove that.

### Findings, fixes, controls

| # | Sev | Finding | Fix | Control |
|---|---|---|---|---|
| 1 | CRITICAL | `workspace` accepted any absolute path from a project `.kit.toml`. `workspace = "$HOME/.claude/skills"` made provisioning create `~/.claude/skills/<repo> -> <repo>`, so a PR-authored root `SKILL.md` became a live skill, loaded in the same session because the hook emits `reloadSkills` | moved to the OPERATOR tier. Constraining it to "under the repo or the home" would not have closed it: `$HOME/.claude/skills` IS under the home | below |
| 2 | HIGH | `map` accepted any absolute path, so a project value printed a file from outside the repo into model context | stays project-tier, resolved by `repo_path` | below |
| 3 | HIGH | `rules` same shape | stays project-tier, resolved by `repo_path`; a refused value falls back to the kit's own template | below |
| 4 | MEDIUM | `op_version` was project-tier and selected a binary that is downloaded, `chmod +x`, prepended to PATH and persisted into `CLAUDE_ENV_FILE`, interpolated unvalidated into the URL | moved to OPERATOR and validated against `^v?[0-9]+(\.[0-9]+)*$` | below |
| 5 | HIGH | the suite passed 118/118 with the `CLAUDE_CODE_REMOTE` gate DEAD in both hooks. The static check grepped comments, and `guard_off()` plus the OFF session-start run had no `ON_PATH`, so the macOS `uname` gate short-circuited before the cloud gate was read | `has_gate` matches the executable line; both OFF entry points carry `ON_PATH`; a Darwin-stub block pins the Linux gate on its own | below |
| 6 | MEDIUM | `install_op`'s curl had no `--max-time` while both siblings cap theirs, and it leaked its `mktemp -d` on every path | `--max-time 120` and an explicit `rm -rf` on both paths | shellcheck + suite green |
| 7 | MEDIUM | the 60s cap bounds ONE clone. Three siblings plus the 150s gh install exceed the SessionStart budget, and blowing it kills the whole hook | a 90s total deadline on the loop, reported as a `!!` line naming the skipped siblings | suite green; the unreachable-sibling row still lands `CLOUD-PARTIAL` |
| 8 | MEDIUM | `cloud.sh` said "Every verb exits 0 by design" while the unknown-verb path exits 1, which a typo in the Setup-script field turns into an aborted session | the exception is named in `cloud.sh`, and the README marks its `\|\| true` load-bearing | `bin/cloud rejects an unknown verb (exit 1)` already asserts the behavior |
| 9 | MEDIUM | the global `git config --global --add safe.directory` write sat outside any gate, so a hand-run on a Mac mutated `~/.gitconfig` | gated to `CLAUDE_CODE_REMOTE=true` AND Linux | suite green |
| 10 | overclaim | the PR body and `SPEC.md` said the tier lint means "the next key cannot silently pick the wrong tier". It checks CONSISTENCY, not CORRECTNESS, and all three holes above passed it | claim softened in `SPEC.md`, the README and `provision.sh`; the correctness half is `repo_path` plus the `op_version` shape check | the new 5b-3 assertions |
| 11 | unverified | whether a repo-committed `.claude/settings.json` `env` block reaches a hook subprocess in a cloud VM | see "Environment trust" below | none possible off-platform |

### Control: each key, before and after

Same hostile `.kit.toml` run against the unfixed branch (`0448b56`) and the
fixed one (`547076e`), through a `uname` stub answering Linux.

```
=========== workspace: [cloud] workspace = $HOME/.claude/skills ===========
BEFORE   ~/.claude/skills/repo -> CREATED (.../repo)  <-- the PR SKILL.md is now a live skill
AFTER    ~/.claude/skills/repo -> not created
positive control:
AFTER    $W/ws-operator/repo symlink: present          (operator tier still sets it)

=========== map: [cloud] map = an absolute path outside the repo ===========
BEFORE   cloud map -> SECRET OUTSIDE THE REPO
AFTER    cloud map ->   !! map: '/.../.secret-outside-repo' is absolute; a project
                        key may only name a path inside this repo
positive control AFTER (repo-relative map) -> IN-REPO MAP MARKER

=========== rules: [cloud] rules = an absolute path outside the repo ===========
BEFORE   cloud rules -> SECRET OUTSIDE THE REPO
AFTER    cloud rules ->   !! rules: '/.../.secret-outside-repo' is absolute; a project
                          key may only name a path inside this repo
                          # Cloud session rules (portable template)   <-- safe fallback
positive control AFTER (repo-relative rules) -> IN-REPO RULES MARKER

=========== op_version: a traversal-shaped pin in the download URL ===========
BEFORE   URL -> https://cache.agilebits.com/dist/1P/op2/pkg/vEVIL/../../../../attacker-path/op_linux_arm64_vEVIL/../../../../attacker-path.zip
AFTER    URL -> https://cache.agilebits.com/dist/1P/op2/pkg/v2.31.1/op_linux_arm64_v2.31.1.zip
positive control AFTER (a real pin from the operator tier):
AFTER    URL -> https://cache.agilebits.com/dist/1P/op2/pkg/v2.30.0/op_linux_arm64_v2.30.0.zip
```

The `..` traversal and the committed-symlink shapes of the same three escapes
are asserted in the suite, section 5b-3, not only here.

### Control: the gate suite goes red, per gate

Each run neuters ONE gate by changing `|| exit 0` to `|| :`, leaving the literal
variable name in place, then restores. Tree clean after each.

| Neutered | Result |
|---|---|
| nothing (baseline) | `PASS 146  FAIL 0`, exit 0 |
| `CLAUDE_CODE_REMOTE` in BOTH hooks | `PASS 134  FAIL 6`, exit 1 |
| `CLAUDE_CODE_REMOTE` in `cloud-session-start.sh` only | `PASS 136  FAIL 4`, exit 1 |
| `CLAUDE_CODE_REMOTE` in `cloud-dash-guard.sh` only | `PASS 137  FAIL 3`, exit 1 |
| the Linux gate in BOTH hooks | `PASS 142  FAIL 4`, exit 1 |

The both-hooks cloud-gate run:

```
FAIL cloud-session-start.sh gates on CLAUDE_CODE_REMOTE
FAIL cloud-dash-guard.sh gates on CLAUDE_CODE_REMOTE
FAIL dash guard OFF leaves the file byte-identical
FAIL session-start hook OFF is silent
FAIL session-start hook OFF assembled nothing
FAIL NC: the same re-invocation with nothing planted exits 0
PASS 134  FAIL 6
```

Before this round the identical mutation produced `smoke: all 118 passed`.

### Suites at `547076e`

| Suite | Result |
|---|---|
| `bash lib/cloud/tests/smoke.sh` | `smoke: all 146 passed`, exit 0 |
| `bash tests/test-meta.sh` | `Passed: 799 / 799`, exit 0 |
| `bash tests/test-hooks.sh` | `Passed: 492 / 492`, exit 0 |
| `bash tests/test-bin-forwarders.sh` | `all 33 passed, 0 skipped`, exit 0 |
| `bash tests/test-install-modules.sh` | `37 passed, 0 failed`, exit 0 |
| `bash tests/test-adopt.sh` | `PASS=21 FAIL=0`, exit 0 |
| `bash tests/test-config-registry.sh` | `19/19 passed`, exit 0 |
| `bash tests/test-kit-contract.sh` | `23 passed, 2 failed`, exit 1. BASELINED: pristine `master` at `e7adc2a` fails the SAME two, both `lib/bench` |
| `shellcheck -S warning lib/cloud/*.sh lib/cloud/tests/smoke.sh hooks/cloud-*.sh bin/cloud` | empty, exit 0 |

### Environment trust (finding 11)

The `CLOUD_<KEY>` env tier is KEPT for operator keys. Removing it was the
reviewer's stated preference and it was rejected, for one reason:
`CLOUD_PROVISION`, the master switch for the whole module, is env-only and has
no config channel. An actor who can set environment variables in a cloud VM
turns the module on and owns it regardless of where the individual keys resolve,
so removing the key tier alone closes nothing while costing the operator their
only per-environment channel (the kit-root `kit.toml` arrives inside the git
clone).

What was hardened instead, because it was a real second door to the same room:
the kit-root config path is now PINNED to the kit install `provision.sh` belongs
to. `kit-config.sh` otherwise reads `KIT_CONFIG_ROOT`/`DWARVES_KIT` from the
environment, so the operator-owned half of the tier split could have been
redirected at a `kit.toml` committed inside the repo.

The environment is therefore documented as the trust anchor in `SPEC.md` and in
the README, not as a convenience.

## Not proved here

See the "Not covered here" table in `docs/verification/cloud-session-support.md`
for the full list, including the two installs that only a real cloud VM can
prove and the CI leg that has not been dispatched. Added by this round:

| Claim | Status |
|---|---|
| a repo-committed `.claude/settings.json` `env` block does NOT reach a hook subprocess in a cloud VM | UNVERIFIED, and it is the load-bearing assumption under the operator tier. If it DOES reach one, a PR can set `CLOUD_PROVISION=1` plus any operator key and the tier split is bypassed. That needs a kit-wide env-hardening pass, not a cloud-local one. Only a real cloud VM answers it |
| the 90s sibling-clone budget is the right number against the real SessionStart timeout | UNVERIFIED. The platform's hook timeout is not documented; 90s leaves room for the 150s gh install under a 300s assumption. A real VM run calibrates it |
| the `safe.directory` gate does not break a real cloud session | UNVERIFIED on the platform. The write now needs `CLAUDE_CODE_REMOTE=true` and Linux, which is exactly the context the comment names, but only a VM run confirms root still resolves the repo root there |
