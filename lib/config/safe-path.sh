#!/bin/bash
# safe-path.sh -- the one guard for kit code that reads or writes a fixed repo-relative path.
# A repo can track a symlink at CLAUDE.md, _meta, .claude/backups and the like. Following it
# makes the kit read or write an operator file outside the project. Source this file; it only
# defines a function.

# kit_refuse_symlink_path <root> <path>... -- return 1, naming the cause on stderr, when a <path>
# or any directory between <root> and it is a symlink, uses "..", or resolves outside the
# physical <root>. A path that does not exist yet passes if every ancestor that exists passes.
kit_refuse_symlink_path() {
  local root="${1%/}" root_real p rel cur seg anc anc_real
  local -a segs
  shift
  root_real="$(cd "$root" 2>/dev/null && pwd -P)" \
    || { echo "refusing '$root': cannot resolve the project root" >&2; return 1; }
  for p in "$@"; do
    rel="${p#"$root"/}"
    [ "$rel" != "$p" ] && [ -n "$rel" ] \
      || { echo "refusing '$p': not under the project root '$root'" >&2; return 1; }
    cur="$root"
    IFS=/ read -ra segs <<< "$rel"
    for seg in "${segs[@]}"; do
      [ -n "$seg" ] || continue
      [ "$seg" != ".." ] || { echo "refusing '$p': contains '..'" >&2; return 1; }
      cur="$cur/$seg"
      [ ! -L "$cur" ] || { echo "refusing '$cur': it is a symlink" >&2; return 1; }
    done
    anc="$(dirname "$p")"
    while [ ! -d "$anc" ] && [ "$anc" != "/" ]; do anc="$(dirname "$anc")"; done
    anc_real="$(cd "$anc" 2>/dev/null && pwd -P)" \
      || { echo "refusing '$p': cannot resolve its directory" >&2; return 1; }
    case "$anc_real/" in
      "$root_real"/*) ;;
      *) echo "refusing '$p': resolves outside the project root" >&2; return 1 ;;
    esac
  done
  return 0
}
