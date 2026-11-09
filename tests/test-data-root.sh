#!/usr/bin/env bash
# test-data-root.sh -- SPEC-418: one resolver for the kit's runtime data paths.
#
# Every case runs under `env -i` with a temp HOME, a pinned operator config dir and a pinned kit
# root, so no case reads the host's real state, config, or kit.toml.
#
#   1 fresh HOME           every entry resolves to the XDG layout, none under ~/.claude
#   2 entry env var wins   over KIT_DATA_ROOT, the operator key and legacy data
#   3 KIT_DATA_ROOT        state and cache move under it; config does not
#   4 operator key         beats XDG and legacy; KIT_DATA_ROOT beats the key; ~ expands
#   5 legacy wins          when it exists and the default path does not; default wins if both exist
#   6 config data where    names legacy or new per entry
#   7 config data move     dry run changes nothing; --apply moves; a rerun is a no-op; skips
#   8 Python door          kit_data.path agrees with the shell resolver
#   9 rewired hooks        a hook writes its state where the resolver says, legacy first
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RES="$KIT_DIR/lib/config/data-path.sh"
DATA="$KIT_DIR/lib/config/data.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1" >&2; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }

T="$(mktemp -d "${TMPDIR:-/tmp}/kit-data.XXXXXX")" || exit 1
trap 'rm -rf "$T"' EXIT
H="$T/home"; OP="$T/op"; KR="$T/kitroot"
mkdir -p "$H" "$OP" "$KR"

# r <extra env...> -- <args...> : run data-path.sh with a clean env.
r() {
  local -a e=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do e+=("$1"); shift; done
  shift
  env -i PATH="$PATH" HOME="$H" KIT_CONFIG_OPERATOR="$OP" KIT_CONFIG_ROOT="$KR" ${e[@]+"${e[@]}"} bash "$RES" "$@"
}
d() {
  local -a e=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do e+=("$1"); shift; done
  shift
  env -i PATH="$PATH" HOME="$H" KIT_CONFIG_OPERATOR="$OP" KIT_CONFIG_ROOT="$KR" ${e[@]+"${e[@]}"} bash "$DATA" "$@"
}

ENTRIES="$(bash "$RES" entries)"

echo "== 1 fresh HOME: XDG layout only =="
all_xdg=0
while read -r kind name; do
  p="$(r -- path "$kind" "$name")"
  case "$kind" in
    state) want="$H/.local/state/dwarves-kit/$name" ;;
    cache) want="$H/.cache/dwarves-kit/$name" ;;
    config) want="$OP/$name" ;;
  esac
  [ "$p" = "$want" ] || { all_xdg=1; bad "fresh $kind $name -> $p (want $want)"; }
  [ "$(r -- source "$kind" "$name")" = default ] || { all_xdg=1; bad "fresh $kind $name source"; }
done <<< "$ENTRIES"
[ "$all_xdg" = 0 ] && ok "every entry resolves to the XDG layout on a fresh HOME"
eq "XDG_STATE_HOME is honored" "$(r XDG_STATE_HOME="$T/xs" -- path state harvest)" "$T/xs/dwarves-kit/harvest"
eq "XDG_CACHE_HOME is honored" "$(r XDG_CACHE_HOME="$T/xc" -- path cache context-hints)" "$T/xc/dwarves-kit/context-hints"
eq "an unknown entry fails" "$(r -- path state nope 2>/dev/null; echo "rc=$?")" "rc=1"

echo "== 2 the entry's own env var wins =="
mkdir -p "$H/.claude/dwarves-kit/state/harvest"
printf '[data]\nroot = "%s"\n' "$T/keyroot" > "$OP/kit.toml"
eq "HARVEST_STATE_DIR beats KIT_DATA_ROOT, the key and legacy" \
   "$(r HARVEST_STATE_DIR="$T/pin" KIT_DATA_ROOT="$T/envroot" -- path state harvest)" "$T/pin"
eq "...and says env" "$(r HARVEST_STATE_DIR="$T/pin" -- source state harvest)" env
eq "a file entry: MONEY_GATE_LOG wins" "$(r MONEY_GATE_LOG="$T/m.log" -- path state money-gate.log)" "$T/m.log"
eq "an empty entry var is ignored" "$(r HARVEST_STATE_DIR= KIT_DATA_ROOT="$T/envroot" -- path state harvest)" "$T/envroot/state/harvest"
rm -f "$OP/kit.toml"; rm -rf "$H/.claude"

echo "== 3 KIT_DATA_ROOT =="
eq "state under the root" "$(r KIT_DATA_ROOT="$T/rt" -- path state intake-sweep)" "$T/rt/state/intake-sweep"
eq "cache under the root" "$(r KIT_DATA_ROOT="$T/rt" -- path cache backlog-stage)" "$T/rt/cache/backlog-stage"
eq "config stays in the config dir" "$(r KIT_DATA_ROOT="$T/rt" -- path config board.json)" "$OP/board.json"
eq "source says root-env" "$(r KIT_DATA_ROOT="$T/rt" -- source state intake-sweep)" root-env
eq "an empty KIT_DATA_ROOT is ignored" "$(r KIT_DATA_ROOT= -- path state intake-sweep)" "$H/.local/state/dwarves-kit/intake-sweep"
mkdir -p "$H/.claude/dwarves-kit/state/intake-sweep"
eq "the root beats legacy data (an explicit choice)" "$(r KIT_DATA_ROOT="$T/rt" -- path state intake-sweep)" "$T/rt/state/intake-sweep"
rm -rf "$H/.claude"

echo "== 4 operator kit.toml key =="
printf '[data]\nroot = "%s"\n' "$T/keyroot" > "$OP/kit.toml"
eq "the key beats XDG" "$(r -- path state harvest)" "$T/keyroot/state/harvest"
eq "...and says root-key" "$(r -- source state harvest)" root-key
eq "KIT_DATA_ROOT beats the key" "$(r KIT_DATA_ROOT="$T/envroot" -- path state harvest)" "$T/envroot/state/harvest"
mkdir -p "$H/.claude/dwarves-kit/state/harvest"
eq "the key beats legacy data" "$(r -- path state harvest)" "$T/keyroot/state/harvest"
printf '[data]\nroot = "~/mydata"\n' > "$OP/kit.toml"
eq "~ expands to HOME" "$(r -- path cache update-notice)" "$H/mydata/cache/update-notice"
printf '[other]\nroot = "%s"\n' "$T/wrong" > "$OP/kit.toml"
eq "a root key in another section is ignored" "$(r -- source cache update-notice)" default
rm -f "$OP/kit.toml"; rm -rf "$H/.claude"

echo "== 5 legacy wins while it holds data =="
mkdir -p "$H/.claude/dwarves-kit/state/harvest" "$H/.claude/intel" "$H/.cache/backlog-sync" "$H/.claude/logs"
: > "$H/.claude/logs/money-gate.log"
eq "harvest -> legacy" "$(r -- path state harvest)" "$H/.claude/dwarves-kit/state/harvest"
eq "...source legacy" "$(r -- source state harvest)" legacy
eq "intel -> legacy" "$(r -- path state intel)" "$H/.claude/intel"
eq "backlog-sync (a ~/.cache path) -> legacy" "$(r -- path state backlog-sync)" "$H/.cache/backlog-sync"
eq "a file entry -> legacy" "$(r -- path state money-gate.log)" "$H/.claude/logs/money-gate.log"
eq "an entry with no legacy data -> default" "$(r -- path state skill-proposals)" "$H/.local/state/dwarves-kit/skill-proposals"
mkdir -p "$H/.local/state/dwarves-kit/harvest"
eq "once the new path exists it wins" "$(r -- path state harvest)" "$H/.local/state/dwarves-kit/harvest"
eq "...and says default" "$(r -- source state harvest)" default
eq "resolving creates nothing" "$([ -e "$H/.local/state/dwarves-kit/intel" ] && echo yes || echo no)" no

# A legacy symlink to an unmounted disk still counts as data: the cursor is not reset.
H5="$H"; H="$T/home5b"; mkdir -p "$H/.claude/dwarves-kit/state"
ln -s "$T/not-mounted" "$H/.claude/dwarves-kit/state/harvest"
eq "a dangling legacy symlink still resolves to legacy" "$(r -- source state harvest)" legacy
rm -rf "$H"; H="$H5"
# board.json always lived in ~/.config/dwarves-kit: a host whose XDG_CONFIG_HOME points elsewhere keeps reading it.
H5="$H"; H="$T/home5c"; mkdir -p "$H/.config/dwarves-kit"; : > "$H/.config/dwarves-kit/board.json"
eq "board.json: the old ~/.config home wins when the XDG one is empty" "$(r KIT_CONFIG_OPERATOR= XDG_CONFIG_HOME="$T/xc" -- path config board.json)" "$H/.config/dwarves-kit/board.json"
mkdir -p "$T/xc/dwarves-kit"; : > "$T/xc/dwarves-kit/board.json"
eq "...and the XDG one wins once it holds the file" "$(r KIT_CONFIG_OPERATOR= XDG_CONFIG_HOME="$T/xc" -- path config board.json)" "$T/xc/dwarves-kit/board.json"
rm -rf "$H" "$T/xc"; H="$H5"

echo "== 6 config data where =="
W="$(d -- where)"
echo "$W" | grep -E '^state +harvest +new ' >/dev/null && ok "where: harvest new (default path exists)" || bad "where harvest row: $W"
echo "$W" | grep -E '^state +intel +legacy +yes ' >/dev/null && ok "where: intel legacy" || bad "where intel row: $W"
echo "$W" | grep -F 'old data still at' | grep -F "$H/.claude/dwarves-kit/state/harvest" >/dev/null && ok "where: warns about old data left behind" || bad "where note: $W"
echo "$W" | grep -E '^root: ' >/dev/null && ok "where: names the root" || bad "where root line"
eq "config data path prints one path" "$(d -- path state intel)" "$H/.claude/intel"
W2="$(d KIT_DATA_ROOT="$T/rt3" -- where)"
echo "$W2" | grep -F 'WARNING: old data at' | grep -F "$H/.claude/dwarves-kit/state/harvest" >/dev/null && ok "where: an explicit root with old data left behind is a WARNING" || bad "where warning: $W2"

echo "== 7 config data move =="
rm -rf "$H" ; mkdir -p "$H"
mkdir -p "$H/.claude/dwarves-kit/state/harvest/sweep" "$H/.claude/dwarves-kit/state/intake-sweep" \
         "$H/.claude/intel" "$H/.claude/logs" "$H/.cache/backlog-sync" "$H/.config/harvest-sweep"
echo cursor > "$H/.claude/dwarves-kit/state/harvest/sweep/cursor.json"
echo keys > "$H/.claude/dwarves-kit/state/intake-sweep/swept-keys.txt"
echo link > "$H/.cache/backlog-sync/github.state.json"
echo line > "$H/.claude/logs/money-gate.log"
echo br > "$H/.config/harvest-sweep/bridge"
snap() { (cd "$H" && { find . | LC_ALL=C sort; find . -type f -exec cksum {} + | LC_ALL=C sort; }); }
S0="$(snap)"
OUT="$(d -- move)"
eq "dry run changes nothing" "$(snap)" "$S0"
echo "$OUT" | grep -F 'would move state/harvest' >/dev/null && ok "dry run lists the harvest move" || bad "dry run output: $OUT"
echo "$OUT" | grep -F 'dry run' >/dev/null && ok "dry run says so" || bad "dry run banner"
OUT="$(d -- move --apply)"
eq "harvest cursor moved intact" "$(cat "$H/.local/state/dwarves-kit/harvest/sweep/cursor.json")" cursor
eq "intake-sweep cursor moved intact" "$(cat "$H/.local/state/dwarves-kit/intake-sweep/swept-keys.txt")" keys
eq "backlog-sync link state moved intact" "$(cat "$H/.local/state/dwarves-kit/backlog-sync/github.state.json")" link
eq "a file entry moved" "$(cat "$H/.local/state/dwarves-kit/money-gate.log")" line
eq "config dir moved" "$(cat "$OP/harvest-sweep/bridge")" br
eq "legacy paths are gone" "$([ -e "$H/.claude/dwarves-kit/state/harvest" ] || [ -e "$H/.cache/backlog-sync" ] && echo left || echo gone)" gone
S1="$(snap)"
OUT2="$(d -- move --apply)"
eq "a rerun moves nothing" "$(echo "$OUT2" | tail -1)" "moved 0"
eq "...and changes nothing" "$(snap)" "$S1"
eq "after the move, the resolver agrees" "$(r -- path state harvest)" "$H/.local/state/dwarves-kit/harvest"
# skips
mkdir -p "$H/.claude/intel" "$H/.local/state/dwarves-kit/intel"
echo old > "$H/.claude/intel/a"; echo new > "$H/.local/state/dwarves-kit/intel/b"
OUT="$(d -- move --apply)"
echo "$OUT" | grep -F 'skip   state/intel: both' >/dev/null && ok "both paths exist: skipped, merge by hand" || bad "both-exist output: $OUT"
eq "...legacy left alone" "$(cat "$H/.claude/intel/a")" old
mkdir -p "$H/.claude/skill-proposals"; echo p > "$H/.claude/skill-proposals/x"
OUT="$(d SKILL_CURATOR_PROPOSALS_DIR="$T/pinned" -- move --apply)"
echo "$OUT" | grep -F 'pinned by SKILL_CURATOR_PROPOSALS_DIR' >/dev/null && ok "an env-pinned entry is skipped" || bad "pinned output: $OUT"
eq "...and not moved" "$([ -e "$H/.claude/skill-proposals/x" ] && echo there)" there
rm -rf "$H/.claude/skill-proposals"; mkdir -p "$T/real"; ln -s "$T/real" "$H/.claude/skill-proposals"
OUT="$(d -- move --apply)"
echo "$OUT" | grep -F 'is a symlink' >/dev/null && ok "a symlinked legacy path is skipped" || bad "symlink output: $OUT"
eq "a bad flag is refused" "$(d -- move --now >/dev/null 2>&1; echo "rc=$?")" "rc=64"
# XDG dirs in this shell are not what a hook or launchd job sees: apply stops, a dry run warns.
mkdir -p "$H/.claude/skill-proposals.x"; rm -rf "$H/.claude/skill-proposals.x"
rm -f "$H/.claude/skill-proposals"; mkdir -p "$H/.claude/skill-curator"; echo c > "$H/.claude/skill-curator/ledger"
OUT="$(d XDG_STATE_HOME="$T/xs7" -- move --apply 2>&1)"; RC=$?
eq "apply stops when XDG_STATE_HOME is set and no root is pinned" "$RC" 1
echo "$OUT" | grep -F 'stop: XDG_STATE_HOME is set' >/dev/null && ok "...and says why" || bad "xdg stop output: $OUT"
eq "...and moved nothing" "$([ -e "$H/.claude/skill-curator/ledger" ] && [ ! -e "$T/xs7" ] && echo kept)" kept
OUT="$(d XDG_STATE_HOME="$T/xs7" -- move 2>&1)"; RC=$?
eq "a dry run warns and still exits 0" "$RC" 0
echo "$OUT" | grep -F 'warning: XDG_STATE_HOME is set' >/dev/null && ok "...with the warning" || bad "xdg warn output: $OUT"
OUT="$(d XDG_STATE_HOME="$T/xs7" KIT_DATA_ROOT="$T/pinroot" -- move --apply 2>&1)"; RC=$?
eq "with a root pinned, XDG dirs do not matter" "$RC" 0
eq "...and the move lands under the root" "$(cat "$T/pinroot/state/skill-curator/ledger" 2>/dev/null)" c
# A leftover .part from an interrupted move is never mistaken for data, and never overwritten.
mkdir -p "$H/.claude/intel" "$H/.local/state/dwarves-kit/intel.part"
rm -rf "$H/.local/state/dwarves-kit/intel"
OUT="$(d -- move --apply 2>&1)"
echo "$OUT" | grep -F 'intel.part is left from an earlier move' >/dev/null && ok "a leftover .part is skipped, not clobbered" || bad "part output: $OUT"
rm -rf "$H/.local/state/dwarves-kit/intel.part"
echo i2 > "$H/.claude/intel/a"
OUT="$(d -- move --apply 2>&1)"
echo "$OUT" | grep -F 're-run: bash deploy/macos/install' >/dev/null && ok "moving intel tells the operator to re-run the kit-weekly install" || bad "intel hint: $OUT"
# KIT_DATA_ROOT redirects the move target
rm -rf "$H"; mkdir -p "$H/.claude/intel"; echo i > "$H/.claude/intel/a"
d KIT_DATA_ROOT="$T/rt2" -- move --apply >/dev/null
eq "move honors KIT_DATA_ROOT" "$(cat "$T/rt2/state/intel/a" 2>/dev/null)" i

echo "== 8 Python door =="
# The real interpreter, not a version-manager shim: the shim would try to install a tool under the temp HOME.
PY="$(python3 -c 'import sys; print(sys.executable)')"
H="$T/home8"; mkdir -p "$H/.claude/intel"
py_all=0
while read -r kind name; do
  sh_p="$(r -- path "$kind" "$name")"
  py_p="$(env -i PATH="$PATH" HOME="$H" KIT_CONFIG_OPERATOR="$OP" KIT_CONFIG_ROOT="$KR" "$PY" -I -c '
import sys; sys.path.insert(0, sys.argv[1]); import kit_data; sys.stdout.write(kit_data.path(sys.argv[2], sys.argv[3]))' \
    "$KIT_DIR/lib/config" "$kind" "$name")"
  [ "$sh_p" = "$py_p" ] || { py_all=1; bad "python $kind $name: '$py_p' vs shell '$sh_p'"; }
done <<< "$ENTRIES"
[ "$py_all" = 0 ] && ok "kit_data.path matches the shell resolver for every entry"
eq "python raises on an unknown entry" "$(python3 -I -c '
import sys; sys.path.insert(0, sys.argv[1]); import kit_data
try: kit_data.path("state", "nope")
except kit_data.KitDataError: print("raised")' "$KIT_DIR/lib/config")" raised

echo "== 9 rewired hooks =="
H="$T/home9"; mkdir -p "$H"
# context-hints keeps one JSON per session under its state dir.
hint() { env -i PATH="$PATH" HOME="$H" KIT_CONFIG_OPERATOR="$OP" KIT_CONFIG_ROOT="$KR" "$@" bash "$KIT_DIR/hooks/context-hints.sh" <<< '{"session_id":"s1","prompt":"hello"}' >/dev/null 2>&1; }
hint
eq "context-hints: a new user's state lands in the XDG cache" "$([ -e "$H/.cache/dwarves-kit/context-hints/s1.json" ] && echo yes || echo no)" yes
eq "context-hints: nothing under ~/.claude" "$([ -e "$H/.claude" ] && echo yes || echo no)" no
rm -rf "$H"; mkdir -p "$H/.claude/dwarves-kit/state/context-hints"
hint
eq "context-hints: legacy dir keeps being used" "$([ -e "$H/.claude/dwarves-kit/state/context-hints/s1.json" ] && echo yes || echo no)" yes
eq "context-hints: no new dir created beside it" "$([ -e "$H/.cache/dwarves-kit" ] && echo yes || echo no)" no
rm -rf "$H"; mkdir -p "$H"
hint CONTEXT_HINTS_STATE="$T/pinned-hints"
eq "context-hints: its own env var still wins" "$([ -e "$T/pinned-hints/s1.json" ] && echo yes || echo no)" yes

echo ""
echo "test-data-root: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
