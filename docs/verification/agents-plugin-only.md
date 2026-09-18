# Proof of done: self-heal stale bare agent copies in plugin compat mode

## Claim

On a machine where the kit is registered as a Claude Code plugin, running
`install.sh` now removes any bare `~/.claude/agents/<name>.md` whose name
matches a kit agent, before it does the compat-only shim install.

## Green run

Simulated a plugin-detected `CLAUDE_DIR` with a stale bare `task-verifier.md`
copy, then ran the fixed `install.sh`.

```
Command: bash install.sh   (CLAUDE_DIR=<tmp>, plugin cache present)
Output:  [plugin detected] kit@dwarves-marketplace is installed; runtime comes from the plugin.
         [ok] Removed stale bare agent copy (plugin already provides kit:task-verifier): task-verifier.md
Check:   ls $CLAUDE_DIR/agents/  -> empty
Exit:    0
Verdict: PASS
```

## Negative control

Same fixture, `install.sh` checked out at the parent commit (before this fix).

```
Command: bash <pre-fix install.sh>   (same CLAUDE_DIR fixture)
Output:  [plugin detected] kit@dwarves-marketplace is installed; runtime comes from the plugin.
         (no removal line)
Check:   ls $CLAUDE_DIR/agents/  -> task-verifier.md still present
Verdict: RED, as expected -- the pre-fix installer leaves the stale duplicate
```

## Regression suite

```
Command: bash tests/run-all.sh --changed
Suites:  18 (incl. test-install-compat.sh, test-install-plugin-detect.sh)
Exit:    0
Verdict: PASS
```

## Real-machine cleanup (Han's Air)

`~/.claude/agents/` held 33 files; 29 had a byte-identical-named twin under
`dwarves-kit/agents/` (content had drifted, confirming these were stale, not
live-synced). Moved to `~/.claude/agents.retired-2026-09-18/`, never deleted.
The 4 remaining (`content-ops-technical-writer.md`, `narrative-transcript-miner.md`,
`narrative-writer.md`, `tldraw-offline.md`) have no kit twin and are untouched.
