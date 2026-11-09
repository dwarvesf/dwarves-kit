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

cmd_where() {
  local kind name path src how present left note root_line=""
  printf '%-7s %-20s %-7s %-7s %s\n' KIND NAME HOW DATA PATH
  while read -r kind name; do
    path="$(kit_data_path "$kind" "$name")"; src="$(kit_data_source "$kind" "$name")"
    how="$(_how "$src")"
    present=no; [ -e "$path" ] && present=yes
    printf '%-7s %-20s %-7s %-7s %s\n' "$kind" "$name" "$how" "$present" "$path"
    left="$(kit_data_legacy "$kind" "$name")"
    if [ "$src" != legacy ] && [ "$left" != "$path" ] && [ -e "$left" ]; then
      printf '        note: old data still at %s (run: config data move)\n' "$left"
    fi
  done < <(kit_data_entries)
  if command -v kit_resolve_log_dir >/dev/null 2>&1; then
    path="$(kit_resolve_log_dir 2>/dev/null || true)"
    present=no; [ -e "$path" ] && present=yes
    printf '%-7s %-20s %-7s %-7s %s\n' state logs new "$present" "$path"
    printf '        note: the run logs have their own knob (KIT_LEDGER_DIR or [ledger] location)\n'
  fi
  _kit_data_root_override
  if [ -n "$_KD_ROOT" ]; then
    root_line="$_KD_ROOT ($_KD_ROOT_SRC)"
  else
    root_line="default (XDG state and cache dirs); set KIT_DATA_ROOT or [data] root in your kit.toml to change it"
  fi
  printf '\nroot: %s\n' "$root_line"
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
  _kit_data_default "$kind" "$name"
}

cmd_move() {
  local apply=0 kind name legacy target envname moved=0 waiting=0
  case "${1:-}" in
    "") ;;
    --apply) apply=1 ;;
    *) echo "usage: config data move [--apply]" >&2; return 64 ;;
  esac
  [ "$apply" = 1 ] || echo "dry run: nothing moves without --apply"
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
    if [ "$apply" = 0 ]; then
      echo "would move $kind/$name: $legacy -> $target"; waiting=$((waiting + 1)); continue
    fi
    mkdir -p "$(dirname "$target")"
    mv -n "$legacy" "$target"
    if [ -e "$target" ] && [ ! -e "$legacy" ]; then
      echo "moved  $kind/$name: $legacy -> $target"; moved=$((moved + 1))
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
