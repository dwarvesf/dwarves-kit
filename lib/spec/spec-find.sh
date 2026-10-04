#!/usr/bin/env bash
# spec-find.sh -- sourced resolver: which SPEC files a repo holds, and which one a slug picks.
#
# Specs live in the root docs/specs/ and co-located under <ns>/docs/specs/ (tools/<x>/, ...).
# Every caller that maps a slug to its spec sources this file, so validate-round and ship-gate
# can never disagree on the pick.
#
#   spec_files <root>          one path per line, `<root>/<rel>`, in pick order:
#                              1. <root>/docs/specs/SPEC-*.md, in ls order (today's rule)
#                              2. */docs/specs/SPEC-*.md at most 4 dirs below <root>,
#                                 shallow first, then LC_ALL=C path order
#   spec_for_slug <root> <s>   the first spec_files line that matches <s>: a root file by the
#                              glob SPEC-*-<s>.md, a co-located file only by the exact name
#                              SPEC-<digits>-<s>.md (a glob `*` would span dashes across tools)
#
# Pruned from the walk: every dot-dir (.git, .claude/worktrees/<other branch>), node_modules,
# vendor, target, dist, build. Both functions exit 0 always and set no shell options.

SPEC_FIND_MAXDEPTH=7

spec_files() {
  local root="$1" nl=$'\n' p
  ls "$root"/docs/specs/SPEC-*.md 2>/dev/null
  ( cd -- "$root" 2>/dev/null || exit 0
    find . -maxdepth "$SPEC_FIND_MAXDEPTH" \
      \( -name '.?*' -o -name node_modules -o -name vendor -o -name target -o -name dist -o -name build \) -prune \
      -o -type f -name 'SPEC-*.md' ! -path './docs/specs/*' ! -path "*${nl}*" -print 2>/dev/null ) \
    | awk -F/ '$(NF-1) == "specs" && $(NF-2) == "docs" { print NF "\t" $0 }' \
    | LC_ALL=C sort -t "$(printf '\t')" -k1,1n -k2 \
    | cut -f2- \
    | while IFS= read -r p; do printf '%s/%s\n' "$root" "${p#./}"; done
  return 0
}

spec_for_slug() {
  local root="$1" slug="$2" f base num
  [ -n "$slug" ] || return 0
  # Root wins in spec_files order, so a root match returns before the walk.
  f=$(ls "$root"/docs/specs/SPEC-*-"$slug".md 2>/dev/null | head -1 || true)
  if [ -n "$f" ]; then printf '%s\n' "$f"; return 0; fi
  while IFS= read -r f; do
    base="${f##*/}"
    case "$base" in SPEC-*-"$slug".md) ;; *) continue ;; esac
    if [ "${f%/*}" != "$root/docs/specs" ]; then
      num="${base#SPEC-}"; num="${num%-"$slug".md}"
      case "$num" in ''|*[!0-9]*) continue ;; esac
    fi
    printf '%s\n' "$f"
    return 0
  done < <(spec_files "$root")
  return 0
}
