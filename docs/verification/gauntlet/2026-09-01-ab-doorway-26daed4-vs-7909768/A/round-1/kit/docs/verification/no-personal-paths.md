# Proof of done: no operator path in the kit or in what adopt renders (ID-408)

**Date:** 2026-08-21 · **Lane:** normal · **Host:** dev laptop (macOS 26.5, bash 3.2) · **Branch:** `chore/no-personal-paths`

**Change class:** behavioral. `lib/adopt.sh` changes what it writes into a consumer
repo, `lib/sync` drops two defaults, and a new test enters CI.

**Claim, two halves.**

1. RENDER. `lib/adopt.sh` interpolated `KIT_ROOT` (this machine's absolute install
   path) into the WORKFLOW pointer, the CLAUDE.md loader block, the proof marker,
   and the seeded `.kit.toml`. Every adopted repo therefore committed one operator's
   home, and every kit reference in it broke on any other machine. Those six lines now
   render `KIT_REF` (`~/.claude/dwarves-kit`), which the consumer's own shell expands.
   `settings.json` hook commands stay absolute because launchd and the hook runner need
   a real path, but they were already written as `$HOME/.claude/dwarves-kit/hooks/*.sh`
   and are resolved at hook-fire time, not at render time.
2. TREE. No operator path (`/Users/<operator>`, `workspace/<operator>`) or operator
   hostname (`Hans-Air*`, `mini-<operator>`) remains anywhere in the tracked tree. The
   two leak-guard tests that quote these strings as data are the only exceptions.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | Adopt into a fresh repo renders no render-time install path | PASS |
| 2 | Rendered consumer files still resolve the kit (portable `~` / `$HOME` form) | PASS |
| 3 | No operator path or hostname in any tracked file | PASS |
| 4 | `lib/sync` hermes target and home have no default; unset aborts with a message | PASS |
| 5 | Sibling-repo test paths come from `$KIT_SIBLING_ROOT`, skip when unset | PASS |
| 6 | No regression: meta suite and kit-contract match the pre-change baseline | PASS |

## Confirmation run

| Check | Command | Exit | Verdict |
|---|---|---|---|
| The guard itself | `bash tests/test-no-personal-paths.sh` | 0 | PASS (3/3) |
| Adopt behavior | `bash tests/test-adopt.sh` | 0 | PASS |
| Sync adapters | `uv run --with pytest python -m pytest lib/sync/tests -q` | 0 | PASS (232) |
| Hooks | `bash tests/test-hooks.sh` | 0 | PASS (492/492) |
| Board (sibling-path skip) | `bash tests/test-board.sh` | 0 | PASS |
| Weekend batch (sibling-path skip) | `bash tests/test-weekend-batch.sh` | 0 | PASS |
| Foldin hooks (owns a leak-guard) | `bash tests/test-kit-foldin-hooks.sh` | 0 | PASS (94/94) |
| Sync dispatch | `bash tests/test-sync-dispatch.sh` | 0 | PASS |
| Structural | `bash tests/test-meta.sh` | 1 | 808/814, same 6 failures as the pre-change baseline |
| Contract | `bash tests/test-kit-contract.sh` | 1 | 23/25, same 2 failures as the pre-change baseline |

The six `test-meta.sh` failures and the two `test-kit-contract.sh` failures reproduce
on `master` at the branch point (`6a66b0b`), unchanged in count and text. They come
from the `devops-triage` agent landing without its MANUAL/README rows, plus a
pre-existing `lib/bench` module gap. This branch neither adds nor fixes any of them.

## Run detail

```
$ bash tests/test-no-personal-paths.sh
ok - adopt renders no render-time install path into the consumer repo
ok - rendered files still point at the kit (portable ~ or $HOME form)
ok - no operator path or hostname anywhere in the tree

Passed: 3 / 3
All no-personal-paths tests passed.

$ bash tests/test-meta.sh | grep -E 'Passed:|Failed:'
Passed: 808 / 814
Failed: 6

$ cd /path/to/master-checkout && bash tests/test-meta.sh | grep -E 'Passed:|Failed:'
Passed: 808 / 814
Failed: 6
```

Rendered output after the fix, in a throwaway `mktemp -d` repo:

```
CLAUDE.md:  bash ~/.claude/dwarves-kit/bin/classify lane classify "<task>"
CLAUDE.md:  ~/.claude/dwarves-kit/bin/gate ledger
WORKFLOW.md:  `~/.claude/dwarves-kit/WORKFLOW.md`
.kit.toml:  # default at ~/.claude/dwarves-kit/kit.toml
.kit.toml:  # Re-run `bash ~/.claude/dwarves-kit/lib/adopt.sh --refresh <this repo>`
docs/verification/README.md:  bash ~/.claude/dwarves-kit/lib/gate/proof-gate.sh contract "<task>"
.claude/settings.json:  bash $HOME/.claude/dwarves-kit/hooks/<name>.sh   (unchanged, runtime-derived)
```

## NEGATIVE CONTROL

Both halves were driven red independently, then restored.

**NC1, the render half.** Put the proof-marker heredoc back on `KIT_ROOT`:

```
# lib/adopt.sh: $KIT_REF -> $KIT_ROOT in the marker heredoc
$ bash tests/test-no-personal-paths.sh
NOT ok - adopt baked the install path into: /var/folders/.../docs/verification/README.md
Passed: 2 / 3
1 test(s) failed.        # exit 1 -> RED, as expected

# restore
$ bash tests/test-no-personal-paths.sh
Passed: 3 / 3            # exit 0 -> GREEN
```

The render half pins `CLAUDE_PLUGIN_ROOT` to `/opt/kit-root-sentinel` for the adopt
run, so the assertion does not depend on the runner's own install path. An earlier
draft grepped only for `/Users/`, which would have passed vacuously on a Linux runner
whose install path carries no `/Users/` at all.

**NC2, the tree half.** Append an operator hostname to a record:

```
$ printf 'ran on Hans-Air-M4\n' >> docs/verification/one-renderer.md
$ bash tests/test-no-personal-paths.sh
NOT ok - operator path/hostname still present:
docs/verification/one-renderer.md:91:ran on Hans-Air-M4
Passed: 2 / 3            # exit 1 -> RED, as expected

$ git checkout HEAD -- docs/verification/one-renderer.md
$ bash tests/test-no-personal-paths.sh
Passed: 3 / 3            # exit 0 -> GREEN
```

## Why the tree half enumerates through `git ls-files`

A recursive `grep -r` (and `rg`) both miss `kit.toml`: `.gitignore` names it, and it is
force-tracked anyway. `rg` skipped it silently during the sweep, and the real
`hermes_target = "<operator host>"` leak inside it survived until the test ran.
`git ls-files` is exactly the set that ships, so it catches force-tracked files and
excludes untracked build noise such as `__pycache__`.

## Rollback

`git revert` this branch's commits. The change is text plus two Python signature
changes with no schema, data, or state migration, so rollback is a plain revert. The
one operational note: a repo already adopted before this change keeps its baked path
until someone runs `bash lib/adopt.sh --refresh <repo>`, which rewrites the managed
CLAUDE.md block and the WORKFLOW pointer. The proof marker and `.kit.toml` are never
overwritten by design, so those two need a manual edit in already-adopted repos.

## Reproduce

```
bash tests/test-no-personal-paths.sh   # expect: 3/3, exit 0
bash tests/test-adopt.sh               # expect: exit 0
bash tests/test-meta.sh                # expect: 808/814, the 6 baseline failures
```
