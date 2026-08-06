# Proof of done: install-home-sandbox (test-install-compat.sh HOME isolation)

Class: behavioral. Verified 2026-08-01. Three parts: a green real run, a
negative control, and reproducibility.

## Context

`tests/test-install-compat.sh` ran `install.sh` with only `CLAUDE_DIR`
overridden, never `HOME`. Faking a plugin-cache dir under `CLAUDE_DIR` trips
`install.sh`'s compat branch, which unconditionally writes a CLI shim to
`$HOME/.local/bin/<name>` for every known module. With the real `$HOME` in
play this clobbered 4 live shims on 2026-08-01, retargeting them at the
test's own `mktemp` dir; once the test's exit trap deleted that dir, the
shims dangled and broke a live hook. Hand-fixed same day; this closes the
suite-level gap that let it happen.

## GREEN (real run)

Command: `bash tests/test-install-compat.sh`
Exit: 0
VERDICT: PASS
Output:

```
ok   took the compat branch
ok   lib symlink created
ok   WORKFLOW.md symlink created
ok   docs/WORKFLOW.md symlink created (SPEC-185 bulk)
ok   AGENTS.md symlink created
ok   settings.json NOT written (no double hooks)
ok   compat lib resolves to a real script
ok   KIT_FORCE_FULL bypasses compat
ok   tripwire: real ~/.local/bin shims never point into this test's $TMPDIR (leaked: none)
PASS: install compat
```

Command: `bash tests/test-meta.sh`
Exit: 0
VERDICT: PASS
Output excerpt:

```
=== Results ===
Passed: 806 / 806
All meta tests passed.
```

## NEGATIVE CONTROL (revert -> RED -> restore)

Reverted the first `install.sh` call back to unsandboxed
(`CLAUDE_DIR="$TMP" bash "$KIT_DIR/install.sh"`, dropping the `HOME="$HOME_SB1"`
prefix) and ran it under a throwaway fake "real HOME" so the demonstration
never touches this machine's actual `~/.local/bin`.

Command:
```
cp tests/test-install-compat.sh tests/test-install-compat-revert.sh
# (edit: drop HOME="$HOME_SB1" from the first install.sh call)
FAKE_REAL_HOME="$(mktemp -d)"; mkdir -p "$FAKE_REAL_HOME/.local/bin"
HOME="$FAKE_REAL_HOME" bash tests/test-install-compat-revert.sh
```

Exit while reverted: 1

```
ok   took the compat branch
ok   lib symlink created
ok   WORKFLOW.md symlink created
ok   docs/WORKFLOW.md symlink created (SPEC-185 bulk)
ok   AGENTS.md symlink created
ok   settings.json NOT written (no double hooks)
ok   compat lib resolves to a real script
ok   KIT_FORCE_FULL bypasses compat
```

Script aborts (`set -euo pipefail`) at `[ -z "$LEAKED" ]` once the tripwire
finds the leak, matching the existing `cmd; chk ... $?` idiom this file
already uses for every other check. Real cause, confirmed on disk:

```
$ ls "$FAKE_REAL_HOME/.local/bin"
board  prose-rag  session  worktree-provision
```

All 4 shims leaked into the fake "real" HOME, each `exec`-ing into the
test's own `$TMP`, the exact incident class from 2026-08-01, reproduced
and caught.

Restore: `rm -f tests/test-install-compat-revert.sh` (temp file, never
committed; the real fix in `tests/test-install-compat.sh` was untouched
throughout this control).

## Reproducibility

Both `Command:` lines above are re-runnable as-is from a clean checkout;
no fixture setup beyond what the suites already do inline.
