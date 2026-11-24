#!/usr/bin/env bash
# spec-active.sh -- the one answer to "which spec is the active one", sourced or run as a CLI.
#
# Callers asked this three ways before: the ship gate by slug and status-blind, the compaction hooks
# by highest open number, the readiness hook by branch token. Each caller now passes its question
# as an argument and gets one answer.
#
#   spec_active [--live | --set] (--slug S | --branch B) <root>
#
#   default   enforcement: the name pick only, spec_for_slug <root> <slug> (root docs/specs, then
#             co-located */docs/specs). Never filters on Status: a ship flips the spec to SHIPPED
#             before the push, and a filter would drop the spec at the gate.
#   --live    session hooks: root docs/specs only, no find. The name pick counts only while its
#             spec is open. Otherwise one open spec wins; several open, the one whose slug tokens
#             appear as whole tokens in the branch (split on / _ . -); else ambiguous.
#   --set     every open spec at root docs/specs, one per line.
#
#   --branch B takes the slug as ${B#*/} (the rule ship-gate and gate-ledger use). --slug S is a slug
#   as given; --live matches tokens against it as the branch. An empty value means no slug.
#   A spec with no Status: header is open. Open states are declared in states.tsv, read by
#   spec-status.sh in one pass.
#
# stdout: one line per spec, `<kind><TAB><path>`; kind is name, live, branch or ambiguous (one line
# per candidate). Paths are `<root>/<rel>`. An enforcement caller reads only the `name` line.
# exit: 0 resolved (or --set with at least one); 1 none; 2 ambiguous; 64 usage.
# Sets no shell option and writes nothing. A caller that cannot read this file treats a missing
# function as "none".

_SPEC_ACTIVE_DIR="${BASH_SOURCE[0]%/*}"
case "${BASH_SOURCE[0]}" in */*) ;; *) _SPEC_ACTIVE_DIR="." ;; esac

if ! type spec_for_slug >/dev/null 2>&1; then
  # shellcheck source=lib/spec/spec-find.sh
  . "$_SPEC_ACTIVE_DIR/spec-find.sh" 2>/dev/null || true
fi

spec_active() {
  local mode=name root="" slug="" branch="" have_id=0 f base files=() live="" name="" n
  local btok="" part tok hit matched="" nmatch=0 toks=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --live) mode=live; shift ;;
      --set) mode="set"; shift ;;
      --slug) [ $# -ge 2 ] || return 64; slug="$2"; branch="$2"; have_id=1; shift 2 ;;
      --branch) [ $# -ge 2 ] || return 64; branch="$2"; slug="${2#*/}"; have_id=1; shift 2 ;;
      -*) echo "spec_active: unknown argument $1" >&2; return 64 ;;
      *) [ -z "$root" ] || return 64; root="$1"; shift ;;
    esac
  done
  [ -n "$root" ] || { echo "usage: spec_active [--live|--set] (--slug S|--branch B) <root>" >&2; return 64; }

  if [ "$mode" = name ]; then
    [ "$have_id" -eq 1 ] || { echo "usage: spec_active needs --slug or --branch" >&2; return 64; }
    f=$(spec_for_slug "$root" "$slug" 2>/dev/null || true)
    [ -n "$f" ] || return 1
    printf 'name\t%s\n' "$f"
    return 0
  fi

  for f in "$root"/docs/specs/SPEC-*.md; do [ -f "$f" ] && files+=("$f"); done
  [ "${#files[@]}" -gt 0 ] || return 1
  if [ -r "$_SPEC_ACTIVE_DIR/spec-status.sh" ]; then
    live=$(bash "$_SPEC_ACTIVE_DIR/spec-status.sh" live --none live "${files[@]}" 2>/dev/null || true)
  else
    live=$(printf '%s\n' "${files[@]}")
  fi
  [ -n "$live" ] || return 1

  if [ "$mode" = set ]; then
    while IFS= read -r f; do [ -n "$f" ] && printf 'live\t%s\n' "$f"; done <<< "$live"
    return 0
  fi

  if [ -n "$slug" ]; then
    for f in "${files[@]}"; do
      base="${f##*/}"
      case "$base" in SPEC-*-"$slug".md) name="$f"; break ;; esac
    done
    if [ -n "$name" ]; then
      case $'\n'"$live"$'\n' in *$'\n'"$name"$'\n'*) printf 'name\t%s\n' "$name"; return 0 ;; esac
    fi
  fi

  n=$(printf '%s\n' "$live" | grep -c . || true)
  if [ "$n" -eq 1 ]; then printf 'live\t%s\n' "$live"; return 0; fi

  if [ -n "$branch" ]; then
    btok=" ${branch//[\/_.-]/ } "
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      part="${f##*/}"; part="${part%.md}"
      [[ $part =~ ^SPEC-[0-9]+-(.*)$ ]] && part="${BASH_REMATCH[1]}"
      hit=0
      IFS=- read -r -a toks <<< "$part"
      for tok in ${toks[@]+"${toks[@]}"}; do
        if [ -n "$tok" ]; then
          case "$btok" in *" $tok "*) hit=1 ;; esac
        fi
      done
      if [ "$hit" -eq 1 ]; then matched="$f"; nmatch=$((nmatch + 1)); fi
    done <<< "$live"
    if [ "$nmatch" -eq 1 ]; then printf 'branch\t%s\n' "$matched"; return 0; fi
  fi

  while IFS= read -r f; do [ -n "$f" ] && printf 'ambiguous\t%s\n' "$f"; done <<< "$live"
  return 2
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  spec_active "$@"
  exit $?
fi
