#!/usr/bin/env bash
# known-failures.sh -- the lead-committed list of failures a tiered mega-goal node may not be charged for.
# Every read is `git show <base>:...`, never the node's tree, so a node cannot edit its own bar.
#
#   read     <root> <base>                 the known failure names at <base>, one per line
#   classify <log> <root> <base> [--exit <n>] [--prev-count <n>] [--base-count <n>] [--known-from <file>]
#                                          prints pass | known | fail; exit 0 for pass and known, 1 for fail.
#                                          known = the run exited non-zero, every failure parsed from the log is
#                                          listed, and the executed count is non-zero and not below --prev-count.
#                                          --base-count <n> is the base run's executed count: known also needs a
#                                          count of at least <n>, and a --base-count with no usable number is
#                                          not proven (fail), so the failure lines are never trusted alone.
#                                          --exit defaults to non-zero: a caller that forgets it cannot get `pass`.
#                                          --known-from replaces the committed list (the wave join passes the
#                                          failure set of its own base run).
#   guard    <root> <base> <goal-file>     exit 1 when the diff touches the known-failures file and the goal file
#                                          carries no `Known-failures: edit <reason>` line
#   names    <log> <root> <base>           the failure names parsed from <log> (sorted, unique)
#   count    <log> <root> <base>           the executed count parsed from <log> (empty when none)
#
# Config, all read at <base> (`.kit.toml` there, then operator and kit-root, never the working tree):
#   [test] known_failures  path of the list, default tests/known-failures.txt
#   [test] failure_line    ERE; capture group 1 is the failure name
#   [test] count_line      ERE; every numeric capture group is summed into the executed count
# A value may be a TOML literal string ('...'), the form a regex needs.
set -uo pipefail
KF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$(cd "$KF_DIR/.." && pwd)"
# shellcheck source=lib/config/kit-config.sh
. "${CONFIG_LIB:-$LIB_ROOT/config/kit-config.sh}" || exit 1

_kf_cfg() {  # root base dotkey [default] -- one layer of single quotes stripped
  local v; v="$(kit_config_get_at "$1" "$2" "$3" "${4:-}")"
  case "$v" in \'*\') v="${v#\'}"; v="${v%\'}" ;; esac
  printf '%s' "$v"
}

# The list's path stays inside the repo: absolute and `..` paths read as a config error.
_kf_path() {  # root base
  local p; p="$(_kf_cfg "$1" "$2" test.known_failures tests/known-failures.txt)"
  case "$p" in /*|..|../*|*/..|*/../*) echo "known-failures: [test] known_failures must be a path inside the repo (got '$p')" >&2; return 2 ;; esac
  printf '%s' "$p"
}

cmd_read() {
  local root="${1:-}" base="${2:-}" p
  [ -n "$root" ] && [ -n "$base" ] || { echo "usage: known-failures.sh read <root> <base>" >&2; return 64; }
  p="$(_kf_path "$root" "$base")" || return 2
  # A name per line; blank lines and `#` comments are not names.
  git -C "$root" show "$base:$p" 2>/dev/null | grep -vE '^[[:space:]]*(#|$)' || true
}

cmd_names() {
  local log="${1:-}" root="${2:-}" base="${3:-}" re line m
  [ -f "$log" ] && [ -n "$root" ] && [ -n "$base" ] || { echo "usage: known-failures.sh names <log> <root> <base>" >&2; return 64; }
  re="$(_kf_cfg "$root" "$base" test.failure_line)"
  [ -n "$re" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ $line =~ $re ]]; then
      m="${BASH_REMATCH[1]-}"; [ -n "$m" ] || m="${BASH_REMATCH[0]}"
      printf '%s\n' "$m"
    fi
  done < "$log" | sort -u
}

cmd_count() {
  local log="${1:-}" root="${2:-}" base="${3:-}" re line g sum last=""
  [ -f "$log" ] && [ -n "$root" ] && [ -n "$base" ] || { echo "usage: known-failures.sh count <log> <root> <base>" >&2; return 64; }
  re="$(_kf_cfg "$root" "$base" test.count_line)"
  [ -n "$re" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ $line =~ $re ]]; then
      sum=0
      for g in "${BASH_REMATCH[@]:1}"; do
        case "$g" in ''|*[!0-9]*) ;; *) sum=$((sum + 10#$g)) ;; esac
      done
      last="$sum"
    fi
  done < "$log"
  printf '%s' "$last"
}

cmd_classify() {
  local log="${1:-}" root="${2:-}" base="${3:-}" ex=1 prev="" kfrom="" known names n c bc="" bc_set=0
  [ -n "$log" ] && [ -n "$root" ] && [ -n "$base" ] || { echo "usage: known-failures.sh classify <log> <root> <base> [--exit <n>] [--prev-count <n>] [--base-count <n>] [--known-from <file>]" >&2; return 64; }
  shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
      --exit) ex="${2:-}"; shift 2 ;;
      --prev-count) prev="${2:-}"; shift 2 ;;
      --base-count) bc_set=1; bc="${2:-}"; shift 2 ;;
      --known-from) kfrom="${2:-}"; shift 2 ;;
      *) echo "known-failures.sh classify: unknown argument '$1'" >&2; return 64 ;;
    esac
  done
  case "$ex" in ''|*[!0-9]*) ex=1 ;; esac
  case "$prev" in ''|*[!0-9]*) prev="" ;; esac
  _kf_fail() { echo "fail"; echo "known-failures: $1" >&2; return 1; }
  [ -f "$log" ] || { _kf_fail "no run log at $log"; return 1; }
  if [ "$ex" -eq 0 ]; then echo "pass"; return 0; fi
  [ -n "$(_kf_cfg "$root" "$base" test.failure_line)" ] || { _kf_fail "no [test] failure_line at the base, so a red run is a plain failure"; return 1; }
  names="$(cmd_names "$log" "$root" "$base")"
  [ -n "$names" ] || { _kf_fail "exit $ex with no parsed failure (a crash is never masked)"; return 1; }
  if [ -n "$kfrom" ]; then known="$(cat "$kfrom" 2>/dev/null)"; else known="$(cmd_read "$root" "$base")" || { _kf_fail "known-failures list unreadable"; return 1; }; fi
  while IFS= read -r n; do
    printf '%s\n' "$known" | grep -qxF -- "$n" || { _kf_fail "new failure: $n"; return 1; }
  done <<EOF
$names
EOF
  [ -n "$(_kf_cfg "$root" "$base" test.count_line)" ] || { _kf_fail "no [test] count_line at the base, so the executed count cannot be checked"; return 1; }
  c="$(cmd_count "$log" "$root" "$base")"
  case "$c" in ''|*[!0-9]*|0) _kf_fail "executed count missing or zero"; return 1 ;; esac
  if [ -n "$prev" ] && [ "$c" -lt "$prev" ]; then _kf_fail "executed count dropped from $prev to $c"; return 1; fi
  if [ "$bc_set" -eq 1 ]; then
    case "$bc" in ''|*[!0-9]*) _kf_fail "the base run's executed count is unavailable, so this run is not proven"; return 1 ;; esac
    if [ "$c" -lt "$bc" ]; then _kf_fail "executed count $c is below the base run's $bc"; return 1; fi
  fi
  echo "known"
}

# The goal file as the base has it. A path inside the repo is read with git show at the base (absent
# there means empty); a path outside the repo is the lead's own file and is read directly.
_kf_goal_text() {  # root base goal-file
  local root="$1" base="$2" gf="$3" abs top rel
  case "$gf" in /*) abs="$gf" ;; *) abs="$root/$gf" ;; esac
  top="$(cd "$root" 2>/dev/null && pwd -P)" || return 0
  [ -d "$(dirname "$abs")" ] && abs="$(cd "$(dirname "$abs")" && pwd -P)/$(basename "$abs")"
  case "$abs" in
    "$top"/*) rel="${abs#"$top"/}"; git -C "$root" show "$base:$rel" 2>/dev/null || true ;;
    *) [ -f "$abs" ] && cat "$abs" || true ;;
  esac
}

cmd_guard() {
  local root="${1:-}" base="${2:-}" gf="${3:-}" p touched
  [ -n "$root" ] && [ -n "$base" ] && [ -n "$gf" ] || { echo "usage: known-failures.sh guard <root> <base> <goal-file>" >&2; return 64; }
  p="$(_kf_path "$root" "$base")" || return 1
  touched="$(git -C "$root" diff --name-only "$base...HEAD" -- "$p" 2>/dev/null; git -C "$root" status --porcelain -- "$p" 2>/dev/null)"
  [ -n "$touched" ] || return 0
  if _kf_goal_text "$root" "$base" "$gf" | grep -qE '^Known-failures:[[:space:]]+edit[[:space:]]+[^[:space:]]'; then return 0; fi
  echo "known-failures: this diff touches $p and the goal file declares no 'Known-failures: edit <reason>'; the lead edits that list, a node does not" >&2
  return 1
}

main() {
  local verb="${1:-}"; shift 2>/dev/null || true
  case "$verb" in
    read) cmd_read "$@" ;;
    classify) cmd_classify "$@" ;;
    guard) cmd_guard "$@" ;;
    names) cmd_names "$@" ;;
    count) cmd_count "$@" ;;
    *) echo "usage: known-failures.sh {read <root> <base>|classify <log> <root> <base> [--exit n] [--prev-count n]|guard <root> <base> <goal-file>|names|count}" >&2; return 64 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
