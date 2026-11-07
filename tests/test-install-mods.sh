#!/usr/bin/env bash
# test-install-mods.sh -- install.sh registers the Claude Code mods (board-pane plus the four
# vendored ones) in every session by default: each installed copy's absolute path joins
# env.CLAUDE_CODE_PLUGIN_DIRS in settings.json (appended with ':', never duplicated, never
# clobbering another entry), `--no-mods` skips them all, a mod whose plugin name another entry
# already loads is skipped, and `--uninstall` removes only the kit's paths and the copied files.
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
append_dir() { # append_dir <home> <dir>: add an entry to the fixture list the way a user would
  local f="$1/.claude/settings.json" tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || return 1
  jq --arg p "$2" '.env.CLAUDE_CODE_PLUGIN_DIRS += ":" + $p' "$f" > "$tmp" && cp "$tmp" "$f"
}
env_key() { jq -r --arg k "$2" '.env[$k] // "<unset>"' "$1/.claude/settings.json"; }
MODS="board-pane secrets-veil memory-lens loop-detective context-inspector"
mod_path() { printf '%s/.claude/dwarves-kit/integrations/claude-code/%s' "$1" "${2:-board-pane}"; }
count_of() { printf '%s' "$2" | tr ':' '\n' | grep -cFx "$1"; }
join_colon() { local out="" p; for p in "$@"; do out="${out:+$out:}$p"; done; printf '%s' "$out"; }
copy_paths() { local m; local -a a=(); for m in $MODS; do a+=("$(mod_path "$1" "$m")"); done; join_colon "${a[@]}"; }
checkout_paths() { local m; local -a a=(); for m in $MODS; do a+=("$KIT_DIR/integrations/claude-code/$m"); done; join_colon "${a[@]}"; }
none_copied() { local m; for m in $MODS; do [ ! -e "$(mod_path "$1" "$m")" ] || return 1; done; }
# A fixture plugin dir: foreign_mod <dir> <plugin name>; no name writes no manifest.
foreign_mod() { mkdir -p "$1/.claude-plugin"; [ -z "${2:-}" ] || printf '{"name":"%s","version":"0.0.1"}\n' "$2" > "$1/.claude-plugin/plugin.json"; }

echo "== fresh install adds the mod path and copies only what the mod loads =="
H1="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
HOME="$H1" bash "$KIT_DIR/install.sh" >"$H1/install.log" 2>&1
MOD1="$(mod_path "$H1")"
ALL1="$(copy_paths "$H1")"
assert_true "fresh install sets env.CLAUDE_CODE_PLUGIN_DIRS to every installed mod path, in list order" "$([ "$(dirs_of "$H1")" = "$ALL1" ]; echo $?)"
assert_true "the board pane manifest and hook module are copied" "$([ -f "$MOD1/.claude-plugin/plugin.json" ] && [ -f "$MOD1/hooks/register.tsx" ]; echo $?)"
for m in $MODS; do
  assert_true "$m: manifest and hooks.json are copied" "$([ -f "$(mod_path "$H1" "$m")/.claude-plugin/plugin.json" ] && [ -f "$(mod_path "$H1" "$m")/hooks/hooks.json" ]; echo $?)"
  assert_true "$m: tests and generated types are not copied" "$([ ! -e "$(mod_path "$H1" "$m")/tests" ] && [ ! -e "$(mod_path "$H1" "$m")/.claude-plugin/types" ]; echo $?)"
done
for m in secrets-veil memory-lens loop-detective context-inspector; do
  assert_true "$m: LICENSE and VENDORED.md travel with the copy" "$([ -f "$(mod_path "$H1" "$m")/LICENSE" ] && [ -f "$(mod_path "$H1" "$m")/VENDORED.md" ]; echo $?)"
done
assert_true "src is copied for the mods that import it" "$([ -f "$(mod_path "$H1" secrets-veil)/src/mask.ts" ] && [ -f "$(mod_path "$H1" memory-lens)/src/memory.ts" ]; echo $?)"

echo "== re-run does not duplicate =="
HOME="$H1" bash "$KIT_DIR/install.sh" >"$H1/install2.log" 2>&1
DUPES1=0
for m in $MODS; do [ "$(count_of "$(mod_path "$H1" "$m")" "$(dirs_of "$H1")")" -eq 1 ] || DUPES1=1; done
assert_true "second run keeps exactly one entry per mod" "$DUPES1"
assert_true "second run leaves the value unchanged" "$([ "$(dirs_of "$H1")" = "$ALL1" ]; echo $?)"

echo "== an existing unrelated path and env key survive =="
H2="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
mkdir -p "$H2/.claude"
printf '{"env":{"CLAUDE_CODE_PLUGIN_DIRS":"/opt/other-mod","KEEP":"1"}}\n' > "$H2/.claude/settings.json"
HOME="$H2" bash "$KIT_DIR/install.sh" >"$H2/install.log" 2>&1
ALL2="$(copy_paths "$H2")"
assert_true "ours are appended after the existing entry with ':'" "$([ "$(dirs_of "$H2")" = "/opt/other-mod:$ALL2" ]; echo $?)"
assert_true "an unrelated env key is untouched" "$([ "$(env_key "$H2" KEEP)" = "1" ]; echo $?)"
HOME="$H2" bash "$KIT_DIR/install.sh" >"$H2/install2.log" 2>&1
assert_true "re-run over a shared value still lists ours once" "$([ "$(dirs_of "$H2")" = "/opt/other-mod:$ALL2" ]; echo $?)"

echo "== uninstall removes only ours =="
HOME="$H2" bash "$KIT_DIR/install.sh" --uninstall >"$H2/uninstall.log" 2>&1
assert_true "the other path stays after uninstall" "$([ "$(dirs_of "$H2")" = "/opt/other-mod" ]; echo $?)"
assert_true "the unrelated env key stays after uninstall" "$([ "$(env_key "$H2" KEEP)" = "1" ]; echo $?)"
assert_true "the copied mod files are removed" "$(none_copied "$H2"; echo $?)"
assert_true "the empty integrations folders are removed" "$([ ! -e "$H2/.claude/dwarves-kit/integrations" ]; echo $?)"
HOME="$H1" bash "$KIT_DIR/install.sh" --uninstall >"$H1/uninstall.log" 2>&1
assert_true "the key is dropped when ours was the only entry" "$([ "$(dirs_of "$H1")" = "<unset>" ]; echo $?)"

echo "== --no-mods skips the mod =="
H3="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
HOME="$H3" bash "$KIT_DIR/install.sh" --no-mods >"$H3/install.log" 2>&1
assert_true "--no-mods leaves env.CLAUDE_CODE_PLUGIN_DIRS unset" "$([ "$(dirs_of "$H3")" = "<unset>" ]; echo $?)"
assert_true "--no-mods copies no mod files" "$(none_copied "$H3"; echo $?)"

echo "== plugin-compat install registers the live checkout path, with no copy =="
compat_home() { # a fixture HOME the installer reads as a plugin machine
  local h; h="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
  mkdir -p "$h/.claude/plugins/cache/dwarves-marketplace/kit/1.0.0/lib"
  printf '%s' "$h"
}
CHECKOUT_ALL="$(checkout_paths)"
H4="$(compat_home)"
printf '{"env":{"CLAUDE_CODE_PLUGIN_DIRS":"/opt/other-mod"}}\n' > "$H4/.claude/settings.json"
HOME="$H4" bash "$KIT_DIR/install.sh" >"$H4/install.log" 2>&1
assert_true "compat mode took the compat branch" "$(grep -q 'plugin detected' "$H4/install.log"; echo $?)"
assert_true "compat appends every checkout path after the existing entry" "$([ "$(dirs_of "$H4")" = "/opt/other-mod:$CHECKOUT_ALL" ]; echo $?)"
assert_true "compat copies no mod files" "$(none_copied "$H4"; echo $?)"
HOME="$H4" bash "$KIT_DIR/install.sh" >"$H4/install2.log" 2>&1
assert_true "compat re-run lists each checkout path once" "$([ "$(dirs_of "$H4")" = "/opt/other-mod:$CHECKOUT_ALL" ]; echo $?)"

echo "== switching between the two installs never loads the mod twice =="
# Separate fixture homes: a full install run over compat symlinks would write through them into
# this checkout, so each direction starts from its own state.
H7="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
mkdir -p "$H7/.claude"
printf '{"env":{"CLAUDE_CODE_PLUGIN_DIRS":"/opt/other-mod:%s"}}\n' "$CHECKOUT_ALL" > "$H7/.claude/settings.json"
HOME="$H7" bash "$KIT_DIR/install.sh" >"$H7/install.log" 2>&1
assert_true "a full install swaps the leftover checkout paths for the copies" "$([ "$(dirs_of "$H7")" = "/opt/other-mod:$(copy_paths "$H7")" ]; echo $?)"
mkdir -p "$H7/.claude/plugins/cache/dwarves-marketplace/kit/1.0.0/lib"
HOME="$H7" bash "$KIT_DIR/install.sh" >"$H7/install2.log" 2>&1
assert_true "a compat run after it swaps the copies for the checkout paths" "$([ "$(dirs_of "$H7")" = "/opt/other-mod:$CHECKOUT_ALL" ]; echo $?)"

echo "== compat uninstall removes the checkout path, keeps the rest =="
HOME="$H4" bash "$KIT_DIR/install.sh" --uninstall >"$H4/uninstall.log" 2>&1
assert_true "uninstall drops the checkout paths and keeps the other entry" "$([ "$(dirs_of "$H4")" = "/opt/other-mod" ]; echo $?)"

echo "== compat --no-mods skips the mod =="
H5="$(compat_home)"
HOME="$H5" bash "$KIT_DIR/install.sh" --no-mods >"$H5/install.log" 2>&1
assert_true "compat --no-mods leaves env.CLAUDE_CODE_PLUGIN_DIRS unset" "$([ "$(dirs_of "$H5")" = "<unset>" ]; echo $?)"
H6="$(compat_home)"
HOME="$H6" bash "$KIT_DIR/install.sh" >"$H6/install.log" 2>&1
assert_true "compat with no settings file creates one holding the checkout paths" "$([ "$(dirs_of "$H6")" = "$CHECKOUT_ALL" ]; echo $?)"
HOME="$H6" bash "$KIT_DIR/install.sh" --uninstall >"$H6/uninstall.log" 2>&1
assert_true "uninstall drops the key when the checkout paths were the only entries" "$([ "$(dirs_of "$H6")" = "<unset>" ]; echo $?)"

echo "== a mod whose plugin name another entry already loads is skipped =="
H9="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
mkdir -p "$H9/.claude"
foreign_mod "$H9/.claude/mods/secrets-veil" secrets-veil          # reached through a leading ~
foreign_mod "$H9/vendor/sv-copy" loop-detective                   # folder name differs: the manifest name decides
foreign_mod "$H9/vendor/context-inspector"                        # no manifest: the folder name decides
foreign_mod "$H9/vendor/unrelated" some-other-plugin              # a different plugin never blocks a kit mod
printf '{"env":{"CLAUDE_CODE_PLUGIN_DIRS":"~/.claude/mods/secrets-veil:%s/vendor/sv-copy:%s/vendor/context-inspector/:%s/vendor/unrelated"}}\n' "$H9" "$H9" "$H9" > "$H9/.claude/settings.json"
FOREIGN9="$(dirs_of "$H9")"
HOME="$H9" bash "$KIT_DIR/install.sh" >"$H9/install.log" 2>&1
assert_true "a ~ entry with the same plugin name skips the kit copy" "$(grep -qF "[skip] secrets-veil already loaded from ~/.claude/mods/secrets-veil" "$H9/install.log"; echo $?)"
assert_true "a different folder name with the same manifest name skips the kit copy" "$(grep -qF "[skip] loop-detective already loaded from $H9/vendor/sv-copy" "$H9/install.log"; echo $?)"
assert_true "a manifest-less entry falls back to its folder name" "$(grep -qF "[skip] context-inspector already loaded from $H9/vendor/context-inspector/" "$H9/install.log"; echo $?)"
assert_true "only the mods without a twin are registered, after the foreign entries" "$([ "$(dirs_of "$H9")" = "$FOREIGN9:$(mod_path "$H9" board-pane):$(mod_path "$H9" memory-lens)" ]; echo $?)"
assert_true "a skipped mod is not copied" "$([ ! -e "$(mod_path "$H9" secrets-veil)" ] && [ ! -e "$(mod_path "$H9" loop-detective)" ] && [ ! -e "$(mod_path "$H9" context-inspector)" ]; echo $?)"
assert_true "a mod with no twin is still copied" "$([ -f "$(mod_path "$H9" memory-lens)/.claude-plugin/plugin.json" ]; echo $?)"
HOME="$H9" bash "$KIT_DIR/install.sh" >"$H9/install2.log" 2>&1
assert_true "a re-run changes nothing" "$([ "$(dirs_of "$H9")" = "$FOREIGN9:$(mod_path "$H9" board-pane):$(mod_path "$H9" memory-lens)" ]; echo $?)"
HOME="$H9" bash "$KIT_DIR/install.sh" --uninstall >"$H9/uninstall.log" 2>&1
assert_true "uninstall leaves the foreign entries exactly as they were" "$([ "$(dirs_of "$H9")" = "$FOREIGN9" ]; echo $?)"
assert_true "uninstall never touches the foreign plugin dirs" "$([ -f "$H9/.claude/mods/secrets-veil/.claude-plugin/plugin.json" ] && [ -f "$H9/vendor/sv-copy/.claude-plugin/plugin.json" ]; echo $?)"

echo "== a foreign twin added after the kit registered its copy retires the kit entry =="
H10="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
HOME="$H10" bash "$KIT_DIR/install.sh" >"$H10/install.log" 2>&1
foreign_mod "$H10/mine/secrets-veil" secrets-veil
append_dir "$H10" "$H10/mine/secrets-veil"
HOME="$H10" bash "$KIT_DIR/install.sh" >"$H10/install2.log" 2>&1
assert_true "the kit entry for the twin is gone, the foreign one stays" "$([ "$(count_of "$(mod_path "$H10" secrets-veil)" "$(dirs_of "$H10")")" -eq 0 ] && [ "$(count_of "$H10/mine/secrets-veil" "$(dirs_of "$H10")")" -eq 1 ]; echo $?)"
assert_true "the other four kit mods stay registered" "$([ "$(count_of "$(mod_path "$H10" board-pane)" "$(dirs_of "$H10")")" -eq 1 ] && [ "$(count_of "$(mod_path "$H10" context-inspector)" "$(dirs_of "$H10")")" -eq 1 ]; echo $?)"

echo "== compat install honors the same guard =="
H11="$(compat_home)"
foreign_mod "$H11/mine/memory-lens" memory-lens
printf '{"env":{"CLAUDE_CODE_PLUGIN_DIRS":"%s/mine/memory-lens"}}\n' "$H11" > "$H11/.claude/settings.json"
HOME="$H11" bash "$KIT_DIR/install.sh" >"$H11/install.log" 2>&1
assert_true "compat skips the checkout path of a mod that is already loaded" "$(grep -qF "[skip] memory-lens already loaded from $H11/mine/memory-lens" "$H11/install.log"; echo $?)"
assert_true "compat registers the other four checkout paths" "$([ "$(dirs_of "$H11")" = "$H11/mine/memory-lens:$KIT_DIR/integrations/claude-code/board-pane:$KIT_DIR/integrations/claude-code/secrets-veil:$KIT_DIR/integrations/claude-code/loop-detective:$KIT_DIR/integrations/claude-code/context-inspector" ]; echo $?)"

echo "== a full install over a compat install never writes into the checkout's kit.toml =="
H8="$(compat_home)"
TOML_SAVED="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
cp "$KIT_DIR/kit.toml" "$TOML_SAVED"
HOME="$H8" bash "$KIT_DIR/install.sh" >"$H8/install.log" 2>&1
assert_true "compat leaves kit.toml as a link into the checkout" "$([ -L "$H8/.claude/dwarves-kit/kit.toml" ]; echo $?)"
HOME="$H8" bash "$KIT_DIR/install.sh" --force-both >"$H8/install-full.log" 2>&1
assert_true "the full install leaves the checkout's kit.toml byte for byte" "$(cmp -s "$TOML_SAVED" "$KIT_DIR/kit.toml"; echo $?)"
assert_true "the full install writes its own kit.toml, not a link" "$([ -f "$H8/.claude/dwarves-kit/kit.toml" ] && [ ! -L "$H8/.claude/dwarves-kit/kit.toml" ]; echo $?)"
# A failing run must not leave the checkout dirty for the next suite.
cmp -s "$TOML_SAVED" "$KIT_DIR/kit.toml" || cp "$TOML_SAVED" "$KIT_DIR/kit.toml"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
