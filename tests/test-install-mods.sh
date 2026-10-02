#!/usr/bin/env bash
# test-install-mods.sh -- install.sh registers the Claude Code board pane mod in every
# session by default: the installed copy's absolute path joins env.CLAUDE_CODE_PLUGIN_DIRS
# in settings.json (appended with ':', never duplicated, never clobbering another entry),
# `--no-mods` skips it, and `--uninstall` removes only that path and the copied files.
#
# Run: bash tests/test-install-mods.sh
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
assert_true() { if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi; }

dirs_of() { jq -r '.env.CLAUDE_CODE_PLUGIN_DIRS // "<unset>"' "$1/.claude/settings.json"; }
env_key() { jq -r --arg k "$2" '.env[$k] // "<unset>"' "$1/.claude/settings.json"; }
mod_path() { printf '%s/.claude/dwarves-kit/integrations/claude-code/board-pane' "$1"; }
count_of() { printf '%s' "$2" | tr ':' '\n' | grep -cFx "$1"; }

echo "== fresh install adds the mod path and copies only what the mod loads =="
H1="$(mktemp -d)"
HOME="$H1" bash "$KIT_DIR/install.sh" >"$H1/install.log" 2>&1
MOD1="$(mod_path "$H1")"
assert_true "fresh install sets env.CLAUDE_CODE_PLUGIN_DIRS to the installed mod path" "$([ "$(dirs_of "$H1")" = "$MOD1" ]; echo $?)"
assert_true "the mod manifest and hook module are copied" "$([ -f "$MOD1/.claude-plugin/plugin.json" ] && [ -f "$MOD1/hooks/register.tsx" ]; echo $?)"
assert_true "tests and generated types are not copied" "$([ ! -e "$MOD1/tests" ] && [ ! -e "$MOD1/.claude-plugin/types" ]; echo $?)"

echo "== re-run does not duplicate =="
HOME="$H1" bash "$KIT_DIR/install.sh" >"$H1/install2.log" 2>&1
assert_true "second run keeps exactly one entry" "$([ "$(count_of "$MOD1" "$(dirs_of "$H1")")" -eq 1 ]; echo $?)"
assert_true "second run leaves the value unchanged" "$([ "$(dirs_of "$H1")" = "$MOD1" ]; echo $?)"

echo "== an existing unrelated path and env key survive =="
H2="$(mktemp -d)"
mkdir -p "$H2/.claude"
printf '{"env":{"CLAUDE_CODE_PLUGIN_DIRS":"/opt/other-mod","KEEP":"1"}}\n' > "$H2/.claude/settings.json"
HOME="$H2" bash "$KIT_DIR/install.sh" >"$H2/install.log" 2>&1
MOD2="$(mod_path "$H2")"
assert_true "ours is appended after the existing entry with ':'" "$([ "$(dirs_of "$H2")" = "/opt/other-mod:$MOD2" ]; echo $?)"
assert_true "an unrelated env key is untouched" "$([ "$(env_key "$H2" KEEP)" = "1" ]; echo $?)"
HOME="$H2" bash "$KIT_DIR/install.sh" >"$H2/install2.log" 2>&1
assert_true "re-run over a shared value still lists ours once" "$([ "$(count_of "$MOD2" "$(dirs_of "$H2")")" -eq 1 ] && [ "$(dirs_of "$H2")" = "/opt/other-mod:$MOD2" ]; echo $?)"

echo "== uninstall removes only ours =="
HOME="$H2" bash "$KIT_DIR/install.sh" --uninstall >"$H2/uninstall.log" 2>&1
assert_true "the other path stays after uninstall" "$([ "$(dirs_of "$H2")" = "/opt/other-mod" ]; echo $?)"
assert_true "the unrelated env key stays after uninstall" "$([ "$(env_key "$H2" KEEP)" = "1" ]; echo $?)"
assert_true "the copied mod files are removed" "$([ ! -e "$MOD2" ]; echo $?)"
HOME="$H1" bash "$KIT_DIR/install.sh" --uninstall >"$H1/uninstall.log" 2>&1
assert_true "the key is dropped when ours was the only entry" "$([ "$(dirs_of "$H1")" = "<unset>" ]; echo $?)"

echo "== --no-mods skips the mod =="
H3="$(mktemp -d)"
HOME="$H3" bash "$KIT_DIR/install.sh" --no-mods >"$H3/install.log" 2>&1
assert_true "--no-mods leaves env.CLAUDE_CODE_PLUGIN_DIRS unset" "$([ "$(dirs_of "$H3")" = "<unset>" ]; echo $?)"
assert_true "--no-mods copies no mod files" "$([ ! -e "$(mod_path "$H3")" ]; echo $?)"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
