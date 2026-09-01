## 2026-08-01 12:00 Sandbox HOME in test-install-compat.sh

### Context

`tests/test-install-compat.sh` runs `install.sh` twice with only `CLAUDE_DIR`
overridden, never `HOME`. Faking a plugin-cache dir under `CLAUDE_DIR` trips
`install.sh`'s compat branch, which unconditionally writes a CLI shim to
`$HOME/.local/bin/<name>` for every known module (board, session,
worktree-provision, prose-rag), regardless of `--with`. With the real `$HOME`
in play, that overwrote 4 live shims on 2026-08-01, retargeting them at the
test's own `mktemp` dir; once the test's `trap ... EXIT` deleted that dir, the
shims dangled and broke a live hook. Hand-fixed same day; this closes the
suite-level gap.

### Decision

Give both `install.sh` invocations in `test-install-compat.sh` their own
`mktemp -d` `HOME` (`HOME_SB1`, `HOME_SB2`), so the compat branch's shim write
lands in a throwaway dir instead of the operator's real `~/.local/bin`. Added
a tripwire check at the end of the same suite: scan the REAL `$HOME/.local/bin`
(the script never reassigns its own `$HOME`, only the install.sh subshells'),
and fail if any dwarves-kit-managed shim's `exec` target points inside this
run's `$TMP`/`$TMP2`.

### Why here, not install.sh itself

`install.sh`'s compat-mode shim write targeting `$HOME/.local/bin` is correct
behavior for a real machine (README Option 2 dev install), the bug is the
*test* exercising that code path without sandboxing, not the script itself.
No other suite hits this: every other `install.sh` invocation in `tests/`
already sets `HOME=` explicitly, or runs the full (non-compat) path with no
`--with`, which enables zero CLI-shim modules by default.

### Verification (revert-to-red proof)

Green, with the fix in place:

```
$ bash tests/test-install-compat.sh
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
Exit: 0
```

Red, with the `HOME_SB1` sandbox reverted (first `install.sh` call restored to
`CLAUDE_DIR="$TMP" bash "$KIT_DIR/install.sh"`, run under a throwaway fake
"real HOME" so the demonstration never touches this machine's actual
`~/.local/bin`):

```
$ FAKE_REAL_HOME="$(mktemp -d)"; mkdir -p "$FAKE_REAL_HOME/.local/bin"
$ HOME="$FAKE_REAL_HOME" bash tests/test-install-compat-revert.sh
ok   took the compat branch
... (unchanged checks) ...
ok   KIT_FORCE_FULL bypasses compat
Exit: 1
$ ls "$FAKE_REAL_HOME/.local/bin"
board  prose-rag  session  worktree-provision   # all 4 shims leaked into the fake real HOME
```

The reverted run aborts (`set -euo pipefail`) at `[ -z "$LEAKED" ]` once the
tripwire finds the leaked shims, exit 1, the same abort-on-failed-assertion
idiom this file already uses for every other `chk` line. Nonzero exit is what
a suite runner checks; the tripwire class of bug is caught.

`bash tests/test-meta.sh`: 806/806 passed, unaffected.

### Impact

No production code changed (`install.sh` untouched). Scope held to the
offending suite; no other test file touched.
