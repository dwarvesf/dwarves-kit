#!/usr/bin/env bash
# test-install-plugin-detect.sh -- install.sh step 3: bare command symlinks are
# created on shell-only installs, skipped (and cleaned up) when the kit is also
# installed as a Claude Code plugin. Runs the full installer with HOME and
# CLAUDE_DIR sandboxed so nothing touches the real ~/.claude or ~/.local/bin.
set -uo pipefail
cd "$(dirname "$0")/.."
KIT_DIR="$(pwd)"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

run_install() { HOME="$1" CLAUDE_DIR="$1/.claude" bash "$KIT_DIR/install.sh" >"$1/install.log" 2>&1; }

# 1. shell-only install (no plugins file) symlinks every command
H1="$(mktemp -d)"; mkdir -p "$H1/.claude"
run_install "$H1"
WANT=$(ls "$KIT_DIR/commands/"*.md | wc -l | xargs)
GOT=$(find "$H1/.claude/commands" -type l 2>/dev/null | wc -l | xargs)
if [ "$GOT" = "$WANT" ]; then ok "shell-only install links every command ($GOT)"; else no "shell-only linked $GOT of $WANT"; fi

# 2. plugin install (kit@* in installed_plugins.json) creates no bare symlinks
H2="$(mktemp -d)"; mkdir -p "$H2/.claude/plugins" "$H2/.claude/commands"
echo '{"version":2,"plugins":{"kit@dwarves-marketplace":[{"scope":"user"}]}}' > "$H2/.claude/plugins/installed_plugins.json"
ln -s "$KIT_DIR/commands/design.md" "$H2/.claude/commands/design.md"   # stale link from an earlier shell install
ln -s /elsewhere/other.md "$H2/.claude/commands/other.md"              # foreign link, must survive
run_install "$H2"
KIT_LINKS=$(find "$H2/.claude/commands" -type l -lname "$KIT_DIR/*" 2>/dev/null | wc -l | xargs)
if [ "$KIT_LINKS" = "0" ]; then ok "plugin install creates no kit-owned bare symlinks"; else no "plugin install left $KIT_LINKS kit-owned symlinks"; fi
if [ ! -e "$H2/.claude/commands/design.md" ]; then ok "stale kit-owned symlink removed"; else no "stale kit-owned symlink survived"; fi
if [ -L "$H2/.claude/commands/other.md" ]; then ok "foreign symlink untouched"; else no "foreign symlink was removed"; fi
grep -q 'Plugin install detected' "$H2/install.log" && ok "install log announces the skip" || no "no detect message in install log"

rm -rf "$H1" "$H2"
echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
