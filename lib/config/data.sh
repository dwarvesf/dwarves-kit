#!/usr/bin/env bash
# data.sh -- `config data`: where the kit keeps its runtime data, and the opt-in move to the new root.
#
# WHY: lib/config/data-path.sh decides every path. This is the human side of it: see each path and
# how it resolved, ask for one path, and move old data to the new root when you choose to.
#
# Verbs:
#   config data [where]          a table: kind, name, path, how it resolved, whether data is there
#   config data path <kind> <name>   the one path, for scripts and skills
#   config data move [--apply]   move data from its legacy path to the new root. Dry run unless
#                                --apply. Never runs by itself. Stop jobs that use the data first
#                                (the harvest sweep LaunchAgent, a running board sync).
#
# `how it resolved` reads: pinned (an entry env var), new (the default or your root), legacy (the old
# path, kept because it holds data and the new path does not). `move` skips an entry when both paths
# exist (merge by hand), when the legacy path is a symlink, and when an env var pins the entry.
set -euo pipefail
DATA_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config/data-path.sh
. "$DATA_SELF/data-path.sh"
# shellcheck source=lib/telemetry/kit-log-dir.sh
. "$DATA_SELF/../telemetry/kit-log-dir.sh" 2>/dev/null || true

_how() {
  case "$1" in
    env) echo pinned ;;
    root-env|root-key|default) echo new ;;
    legacy) echo legacy ;;
  esac
}

# _dev <path> -- the device number of a path, or nothing.
_dev() { stat -c %d "$1" 2>/dev/null || stat -f %d "$1" 2>/dev/null; }

cmd_where() {
  local kind name path src how present left note root_line=""
  _kit_data_root_override
  printf '%-7s %-20s %-7s %-7s %s\n' KIND NAME HOW DATA PATH
  while read -r kind name; do
    path="$(kit_data_path "$kind" "$name")"; src="$(kit_data_source "$kind" "$name")"
    how="$(_how "$src")"
    present=no; [ -e "$path" ] && present=yes
    printf '%-7s %-20s %-7s %-7s %s\n' "$kind" "$name" "$how" "$present" "$path"
    left="$(kit_data_legacy "$kind" "$name")"
    if [ "$src" != legacy ] && [ "$left" != "$path" ] && { [ -e "$left" ] || [ -L "$left" ]; }; then
      case "$src" in
        root-env)
          printf '        WARNING: old data at %s is IGNORED while KIT_DATA_ROOT is set; this entry starts empty. Run: config data move --apply\n' "$left" ;;
        env) printf '        note: old data at %s is not used, %s pins this entry\n' "$left" "$(kit_data_env "$kind" "$name")" ;;
        *) printf '        WARNING: old data at %s and data at %s both exist; the new one is used, merge by hand\n' "$left" "$path" ;;
      esac
    elif [ "$src" = legacy ] && [ -n "$_KD_ROOT" ] && [ "$kind" != config ]; then
      printf '        note: data root is set but this entry has not moved yet (run: config data move)\n'
    fi
  done < <(kit_data_entries)
  if command -v kit_resolve_log_dir >/dev/null 2>&1; then
    path="$(kit_resolve_log_dir 2>/dev/null || true)"
    present=no; [ -e "$path" ] && present=yes
    printf '%-7s %-20s %-7s %-7s %s\n' state logs new "$present" "$path"
    printf '        note: the run logs have their own knob (KIT_LEDGER_DIR or [ledger] location)\n'
  fi
  if [ -n "$_KD_ROOT" ]; then
    root_line="$_KD_ROOT ($_KD_ROOT_SRC)"
  else
    root_line="default (XDG state and cache dirs); set [data] root in your operator kit.toml to change it"
  fi
  printf '\nroot: %s\n' "$root_line"
  [ -z "$_KD_ROOT_BAD" ] || printf 'ignored: %s is not an absolute path\n' "$_KD_ROOT_BAD"
}

cmd_path() {
  [ "$#" -eq 2 ] || { echo "usage: config data path <kind> <name>" >&2; return 64; }
  kit_data_path "$1" "$2"; echo
}

# The path an entry would have if no legacy data existed: what `move` targets.
_target() {
  local kind="$1" name="$2"
  if [ "$kind" != config ]; then
    _kit_data_root_override
    if [ -n "$_KD_ROOT" ]; then printf '%s' "$_KD_ROOT/$kind/$name"; return 0; fi
  fi
  _kit_data_default "$kind" "$name"; printf '%s' "$_KD_DEF"
}

cmd_move() {
  local apply=0 kind name legacy target envname moved=0 waiting=0 xdg=""
  case "${1:-}" in
    "") ;;
    --apply) apply=1 ;;
    *) echo "usage: config data move [--apply]" >&2; return 64 ;;
  esac
  [ "$apply" = 1 ] || echo "dry run: nothing moves without --apply"
  # The target comes from THIS shell's XDG dirs. A hook or a launchd job without them would look
  # elsewhere, find an empty dir, and reset its cursor. Pin the root first.
  _kit_data_root_override
  if [ -z "$_KD_ROOT" ]; then
    [ -z "${XDG_STATE_HOME:-}" ] || xdg="XDG_STATE_HOME"
    [ -z "${XDG_CACHE_HOME:-}" ] || xdg="${xdg:+$xdg and }XDG_CACHE_HOME"
  fi
  if [ -n "$xdg" ]; then
    echo "$([ "$apply" = 1 ] && echo stop || echo warning): $xdg is set in this shell, so the target is not the one a hook or a launchd job would find." >&2
    echo "      Set [data] root = \"<dir>\" in your operator kit.toml (or KIT_DATA_ROOT), then run this again." >&2
    [ "$apply" = 0 ] || return 1
  fi
  while read -r kind name; do
    legacy="$(kit_data_legacy "$kind" "$name")"
    target="$(_target "$kind" "$name")"
    envname="$(kit_data_env "$kind" "$name")"
    if [ -n "$envname" ] && [ -n "${!envname:-}" ]; then
      echo "skip   $kind/$name: pinned by $envname"; continue
    fi
    if [ "$legacy" = "$target" ]; then continue; fi
    if [ ! -e "$legacy" ] && [ ! -L "$legacy" ]; then continue; fi
    if [ -L "$legacy" ]; then
      echo "skip   $kind/$name: $legacy is a symlink, move it by hand"; continue
    fi
    if [ -e "$target" ]; then
      echo "skip   $kind/$name: both $legacy and $target exist, merge by hand"; continue
    fi
    if [ -e "$target.part" ]; then
      echo "skip   $kind/$name: $target.part is left from an earlier move, check it and remove it by hand"; continue
    fi
    if [ "$apply" = 0 ]; then
      echo "would move $kind/$name: $legacy -> $target"; waiting=$((waiting + 1)); continue
    fi
    mkdir -p "$(dirname "$target")"
    # On one disk the move is a single rename: no moment when neither path holds the data. Across
    # disks it copies, so it goes into a .part name first and an interrupted copy never looks like data.
    if [ "$(_dev "$legacy")" = "$(_dev "$(dirname "$target")")" ] && [ -n "$(_dev "$legacy")" ]; then
      mv -n "$legacy" "$target"
    else
      mv -n "$legacy" "$target.part" && [ ! -e "$legacy" ] && mv -n "$target.part" "$target"
    fi
    if [ -e "$target" ] && [ ! -L "$legacy" ] && [ ! -e "$legacy" ]; then
      echo "moved  $kind/$name: $legacy -> $target"; moved=$((moved + 1))
      [ "$name" != intel ] || echo "       the kit-weekly LaunchAgent logs into the old intel dir; re-run: bash deploy/macos/install"
    else
      echo "FAILED $kind/$name: $legacy -> $target" >&2; return 1
    fi
  done < <(kit_data_entries)
  if [ "$apply" = 1 ]; then echo "moved $moved"; else echo "would move $waiting; run again with --apply"; fi
}

usage() {
  cat <<'EOF'
usage: config data [where | path <kind> <name> | move [--apply]]

  config data                  where every kind of data lives and how it resolved
  config data path <kind> <name>   print one path (kind: state, cache, config)
  config data move [--apply]   move data from its old path to the new root (dry run unless --apply)
EOF
}

case "${1:-where}" in
  where) cmd_where ;;
  path) shift; cmd_path "$@" ;;
  move) shift; cmd_move "$@" ;;
  -h|--help|help) usage ;;
  *) echo "config data: unknown verb '$1'" >&2; usage >&2; exit 64 ;;
esac
