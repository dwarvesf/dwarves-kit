# Verification -- quote-plugin-root

Every `hooks/hooks.json` command now double-quotes its `${CLAUDE_PLUGIN_ROOT}` paths, so a plugin root containing a space (Orca's `CLAUDE_CONFIG_DIR` sits under "Application Support") no longer word-splits and silently disables every gate.

## Green run
```
Command: bash tests/test-hooks-plugin-root-space.sh
Exit: 0
Output:
=== hooks.json: the real safety-gate entry, plugin root with a space ===
  PASS  hooks.json has a safety-gate entry
  PASS  quoted entry blocks the bad input through /bin/sh -c (exit 2)
=== negative control: the same entry with its quotes stripped ===
  PASS  unquoted entry does NOT block, the bug reproduces (exit 127)
=== hooks.json: every ${CLAUDE_PLUGIN_ROOT} use sits inside double quotes ===
  PASS  no unquoted ${CLAUDE_PLUGIN_ROOT} in any hooks.json command

Results: 4 passed, 0 failed
Verdict: PASS
```
The three suites that parsed the old unquoted form also pass in full (`bash tests/test-hook-anchor.sh`: 9 passed, 0 failed; `bash tests/test-meta-plugin-hooks.sh`: exit 0; `bash tests/test-hooks.sh`: "All tests passed", including all 14 "anchor: wrapped gate blocks" cases), as do `tests/test-modules-table.sh` and `tests/test-meta-docs-registry.sh` (120 / 120).

## Negative control
```
Command: git show HEAD~1:hooks/hooks.json > hooks/hooks.json; bash tests/test-hooks-plugin-root-space.sh
Exit: 1
Output:
=== hooks.json: the real safety-gate entry, plugin root with a space ===
  PASS  hooks.json has a safety-gate entry
  FAIL  quoted entry blocks the bad input through /bin/sh -c (want exit 2, got 127)
=== negative control: the same entry with its quotes stripped ===
  PASS  unquoted entry does NOT block, the bug reproduces (exit 127)
=== hooks.json: every ${CLAUDE_PLUGIN_ROOT} use sits inside double quotes ===
  FAIL  no unquoted ${CLAUDE_PLUGIN_ROOT} in any hooks.json command
        bash ${CLAUDE_PLUGIN_ROOT}/hooks/anchor-root.sh ${CLAUDE_PLUGIN_ROOT}/hooks/post-compact-reinject.sh

Results: 2 passed, 2 failed
Verdict: RED as expected
```
The old unquoted `hooks.json` was put back from the parent commit, the suite went red (the gate entry cannot even launch: exit 127 here, exit 0 on a host where the split prefix happens to be an empty file), then `git checkout -- hooks/hooks.json` restored the quoted file and the suite is green again.

## Not proven
- `settings.json` (bash-install path) still writes `$HOME/.claude/dwarves-kit/...` unquoted; it expands `$HOME`, not the plugin root, so it breaks only for a home directory containing a space.
- Claude Code itself launching the quoted command: the test drives the same string through `/bin/sh -c`, not through the real harness.
