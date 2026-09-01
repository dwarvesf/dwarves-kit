# Proof of done: installer skips bare command symlinks on plugin installs

Change: install.sh step 3 detects a `kit@*` entry in `$CLAUDE_DIR/plugins/installed_plugins.json`. When present, it removes kit-owned bare symlinks instead of creating them. Shell-only installs keep the old behavior.

Method: full installer run with `HOME` and `CLAUDE_DIR` pointed at a sandbox, so no real `~/.claude` or `~/.local/bin` state is touched. Reproduce with the script below.

## Green run

Command: `bash prove-installer.sh` (sandboxed HOME; two installs: shell-only, then plugin-seeded with one stale kit symlink + one foreign symlink)
Exit: 0
Output:
```
case1 shell-only: symlinks=36 (expect >30)
case2 plugin: kit-owned symlinks=0 (expect 0), foreign link=kept (expect kept)
case2 detect-msg lines: 1
PROOF: PASS
```
Verdict: PASS

## Negative control

Command: `git checkout origin/master -- install.sh && bash prove-installer.sh` (revert), then `git checkout HEAD -- install.sh` (restore)
Exit: 0 (proof script reports FAIL as designed)
Output:
```
case2 plugin: kit-owned symlinks=36 (expect 0)
case2 detect-msg lines: 0
PROOF: FAIL
```
Verdict: RED on revert, restored after. The detect branch is load-bearing.

## Reproduce

```bash
WT=<kit checkout>
SB=$(mktemp -d)
run() { HOME="$1" CLAUDE_DIR="$1/.claude" bash "$WT/install.sh" >"$1/install.log" 2>&1; }
mkdir -p "$SB/shell-only/.claude"; run "$SB/shell-only"
find "$SB/shell-only/.claude/commands" -type l | wc -l                     # expect >30
mkdir -p "$SB/plugin/.claude/plugins" "$SB/plugin/.claude/commands"
echo '{"version":2,"plugins":{"kit@dwarves-marketplace":[{"scope":"user"}]}}' > "$SB/plugin/.claude/plugins/installed_plugins.json"
ln -s "$WT/commands/design.md" "$SB/plugin/.claude/commands/design.md"
run "$SB/plugin"
find "$SB/plugin/.claude/commands" -type l -lname "$WT/*" | wc -l          # expect 0
```
