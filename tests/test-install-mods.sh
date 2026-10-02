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

dirs_of() {
  [ -f "$1/.claude/settings.json" ] || { echo "<unset>"; return; }
  jq -r '.env.CLAUDE_CODE_PLUGIN_DIRS // "<unset>"' "$1/.claude/settings.json"
}
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

echo "== plugin-compat install registers the live checkout path, with no copy =="
compat_home() { # a fixture HOME the installer reads as a plugin machine
  local h; h="$(mktemp -d)"
  mkdir -p "$h/.claude/plugins/cache/dwarves-marketplace/kit/1.0.0/lib"
  printf '%s' "$h"
}
CHECKOUT_MOD="$KIT_DIR/integrations/claude-code/board-pane"
H4="$(compat_home)"
printf '{"env":{"CLAUDE_CODE_PLUGIN_DIRS":"/opt/other-mod"}}\n' > "$H4/.claude/settings.json"
HOME="$H4" bash "$KIT_DIR/install.sh" >"$H4/install.log" 2>&1
assert_true "compat mode took the compat branch" "$(grep -q 'plugin detected' "$H4/install.log"; echo $?)"
assert_true "compat appends the checkout path after the existing entry" "$([ "$(dirs_of "$H4")" = "/opt/other-mod:$CHECKOUT_MOD" ]; echo $?)"
assert_true "compat copies no mod files" "$([ ! -e "$(mod_path "$H4")" ]; echo $?)"
HOME="$H4" bash "$KIT_DIR/install.sh" >"$H4/install2.log" 2>&1
assert_true "compat re-run lists the checkout path once" "$([ "$(count_of "$CHECKOUT_MOD" "$(dirs_of "$H4")")" -eq 1 ] && [ "$(dirs_of "$H4")" = "/opt/other-mod:$CHECKOUT_MOD" ]; echo $?)"

echo "== switching between the two installs never loads the mod twice =="
# Separate fixture homes: a full install run over compat symlinks would write through them into
# this checkout, so each direction starts from its own state.
H7="$(mktemp -d)"
mkdir -p "$H7/.claude"
printf '{"env":{"CLAUDE_CODE_PLUGIN_DIRS":"/opt/other-mod:%s"}}\n' "$CHECKOUT_MOD" > "$H7/.claude/settings.json"
HOME="$H7" bash "$KIT_DIR/install.sh" >"$H7/install.log" 2>&1
assert_true "a full install swaps a leftover checkout path for the copy" "$([ "$(dirs_of "$H7")" = "/opt/other-mod:$(mod_path "$H7")" ]; echo $?)"
mkdir -p "$H7/.claude/plugins/cache/dwarves-marketplace/kit/1.0.0/lib"
HOME="$H7" bash "$KIT_DIR/install.sh" >"$H7/install2.log" 2>&1
assert_true "a compat run after it swaps the copy for the checkout path" "$([ "$(dirs_of "$H7")" = "/opt/other-mod:$CHECKOUT_MOD" ]; echo $?)"

echo "== compat uninstall removes the checkout path, keeps the rest =="
HOME="$H4" bash "$KIT_DIR/install.sh" --uninstall >"$H4/uninstall.log" 2>&1
assert_true "uninstall drops the checkout path and keeps the other entry" "$([ "$(dirs_of "$H4")" = "/opt/other-mod" ]; echo $?)"

echo "== compat --no-mods skips the mod =="
H5="$(compat_home)"
HOME="$H5" bash "$KIT_DIR/install.sh" --no-mods >"$H5/install.log" 2>&1
assert_true "compat --no-mods leaves env.CLAUDE_CODE_PLUGIN_DIRS unset" "$([ "$(dirs_of "$H5")" = "<unset>" ]; echo $?)"
H6="$(compat_home)"
HOME="$H6" bash "$KIT_DIR/install.sh" >"$H6/install.log" 2>&1
assert_true "compat with no settings file creates one holding the checkout path" "$([ "$(dirs_of "$H6")" = "$CHECKOUT_MOD" ]; echo $?)"
HOME="$H6" bash "$KIT_DIR/install.sh" --uninstall >"$H6/uninstall.log" 2>&1
assert_true "uninstall drops the key when the checkout path was the only entry" "$([ "$(dirs_of "$H6")" = "<unset>" ]; echo $?)"

echo "== a full install over a compat install never writes into the checkout's kit.toml =="
H8="$(compat_home)"
TOML_SAVED="$(mktemp)"
cp "$KIT_DIR/kit.toml" "$TOML_SAVED"
HOME="$H8" bash "$KIT_DIR/install.sh" >"$H8/install.log" 2>&1
assert_true "compat leaves kit.toml as a link into the checkout" "$([ -L "$H8/.claude/dwarves-kit/kit.toml" ]; echo $?)"
HOME="$H8" KIT_FORCE_FULL=1 bash "$KIT_DIR/install.sh" >"$H8/install-full.log" 2>&1
assert_true "the full install leaves the checkout's kit.toml byte for byte" "$(cmp -s "$TOML_SAVED" "$KIT_DIR/kit.toml"; echo $?)"
assert_true "the full install writes its own kit.toml, not a link" "$([ -f "$H8/.claude/dwarves-kit/kit.toml" ] && [ ! -L "$H8/.claude/dwarves-kit/kit.toml" ]; echo $?)"
# A failing run must not leave the checkout dirty for the next suite.
cmp -s "$TOML_SAVED" "$KIT_DIR/kit.toml" || cp "$TOML_SAVED" "$KIT_DIR/kit.toml"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
