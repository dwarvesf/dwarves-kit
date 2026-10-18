#!/bin/bash
# intake-sweep.sh -- sweeps a consumer's declared "review later" sources into the backlog staging file; config-gated no-op.
# backlog-stage harvests SESSION transcripts into `_meta/backlog-staging.md`; this feeds the
# same funnel from PERSISTED deferred-link stores a session harvest cannot see (a digest
# ledger, saved browser collections). One funnel, one grammar (lib/reflect/staging-format.jq,
# the jq twin of staging-format.py), one human promote gate (`board promote`). It NEVER
# writes the board (propose, do not dispose).
#
# Config-gated: the kit carries no personal data or source paths. A consumer declares its
# sources in `<repo-root>/_meta/intake-sources.json`; without it the hook is a silent no-op.
#   {"sources": [
#     {"name": "<slug>", "kind": "jsonl", "path": "rel/or/abs.jsonl",
#      "include": {"field": "verdict", "equals": "keep"},
#      "map": {"title": "title", "url": "url", "intent": "conclusion"},
#      "u": "lo", "f": "hi", "home": ""},
#     {"name": "<slug>", "kind": "command", "command": "bin/tool subcmd",
#      "map": {"title": "title", "url": "url"}, "u": "lo", "f": "hi"}]}
#   kind=jsonl    one JSON object per line.
#   kind=command  an argv run from the repo root (split like Python's shlex, never through a
#                 shell) that prints a JSON array of objects.
#
# A source is re-read whole every sweep, so dedup is durable, three layers: (1) the title is
# already on the board or in the staging file, in any block state; (2) the item's URL appears
# anywhere in either file; (3) a swept-keys state file, so a staged key is never proposed again
# even after its block is promoted, renamed, or rejected.
#
# Env:
#   BACKLOG_STAGE_BACKLOG / BACKLOG_STAGE_STAGING   the board and the staging file (the backlog-stage seam)
#   REPO_ROOT                                       repo root (else git's top level, else the cwd)
#   INTAKE_SWEEP_CONFIG=FILE                        config path override
#   INTAKE_SWEEP_MIN_INTERVAL=S                     throttle, default 86400 (daily); 0 turns it off
#   INTAKE_SWEEP_STATE_DIR=DIR                      throttle stamp + swept-keys file (default ~/.claude/dwarves-kit/state/intake-sweep)
#   INTAKE_SWEEP_CMD_TIMEOUT=S                      per-command timeout, default 15
# Flags: --force skips the throttle; --check reports what each source yields raw, before dedup
# (run it after editing the config: a typo'd field map shows up as 0 items, not silence).
# Exit 0 always: a sweep never blocks a session. Behavior is pinned against the Python original
# by tests/test-intake-sweep-parity.sh; a shape the Python crashed on stages nothing.

set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "intake-sweep: jq not found; the sweep is off" >&2; exit 0; }

src="${BASH_SOURCE[0]}"
while [ -h "$src" ]; do
  dir=$(cd -P "$(dirname "$src")" && pwd)
  src=$(readlink "$src")
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
HERE=$(cd -P "$(dirname "$src")" && pwd)
JQLIB="$HERE/../lib/reflect"
# shellcheck source=../lib/reflect/shlex-split.sh
source "$JQLIB/shlex-split.sh"
# shellcheck source=../lib/reflect/hook-util.sh
source "$JQLIB/hook-util.sh"
# shellcheck source=../lib/reflect/staging-format.sh
source "$JQLIB/staging-format.sh"

force=0; check=0
for a in "$@"; do
  case "$a" in --force) force=1 ;; --check) check=1 ;; esac
done

if [ -n "${REPO_ROOT:-}" ]; then
  root=$REPO_ROOT
else
  root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$root" ] || root=$(pwd -P)
fi

W=$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX") || exit 0
trap 'case "$W" in /*/*) command rm -rf -- "$W" ;; esac 2>/dev/null' EXIT

cfg="${INTAKE_SWEEP_CONFIG:-$(hu_join "$root" _meta/intake-sources.json)}"
sources='[]'
if [ -f "$cfg" ] && [ -r "$cfg" ] && hu_utf8_ok "$cfg"; then
  sources=$(jq -c -s 'if length == 1 and (.[0] | type) == "object" and (.[0].sources | type) == "array" then .[0].sources else [] end' "$cfg" 2>/dev/null) || sources='[]'
fi
[ -n "$sources" ] || sources='[]'
count=$(jq 'length' <<<"$sources")

# jq helpers shared by every program below: Python truthiness, str.strip, and the mapping of one
# raw object into {title, url, intent} through the source's field map. A map key, include field,
# kind, or name that is a list or object is unhashable to Python and crashes it.
LIB='include "staging-format";
def truthy: . != null and . != false and . != 0 and . != "" and . != [] and . != {};
def pystrip: gsub("^[\\s\\x1c-\\x1f]+|[\\s\\x1c-\\x1f]+$"; "");
def key($k): if ($k | type) == "array" or ($k | type) == "object" then error("unhashable key") else $k end;
def mapped($src):
  . as $item
  | ($src | sf_get("map"; null) | if truthy then . else {} end) as $m
  | if ($m | type) != "object" then error("map is not an object") else . end
  | def field($k): (key($k)) as $k | if ($k | type) != "string" then "" else ($item | sf_get($k; "") | if truthy then sf_pystr else "" end) end;
    ($m | sf_get("title"; "title")) as $tk
  | ($m | sf_get("url"; "url")) as $uk
  | ($m | sf_get("intent"; null)) as $ik
  | (field($tk)) as $title0
  | (field($uk)) as $url
  | {title: (if ($title0 | test("[^\\s\\x1c-\\x1f]")) then $title0 else $url end),
     url: ($url | pystrip),
     intent: (if $ik | truthy then field($ik) else "" end)};
'

# source_info <source-json>: sets NAME, KIND (its printed form), KNOWN (Y or N). A list or object
# kind is a crash shape (return 1).
source_info() {
  local info
  info=$(jq -j -L "$JQLIB" 'include "staging-format";
    if (sf_get("kind"; "") | type) == "array" or (sf_get("kind"; "") | type) == "object" then error("kind") else . end
    | (sf_get("name"; "?") | sf_pystr), "\u0001", (sf_get("kind"; "") | sf_pystr), "\u0001",
      (sf_get("kind"; "") | if . == "jsonl" or . == "command" then "Y" else "N" end)' <<<"$1" 2>/dev/null) || return 1
  NAME=${info%%$'\001'*}; info=${info#*$'\001'}; KIND=${info%%$'\001'*}; KNOWN=${info#*$'\001'}
}

# read_source <source-json>: writes the source's mapped items as a JSON array to $W/items.json.
# Returns 1 on a shape the Python crashed on (a non-string path or command, an unbalanced quote,
# a map or include that is not an object when an item reaches it), 0 otherwise.
read_source() {
  local s=$1 kind path tag cmd t out rc
  echo '[]' > "$W/items.json"
  kind=$(jq -j 'if has("kind") then .kind else "" end | if . == "jsonl" then "J" elif . == "command" then "C" else "?" end' <<<"$s")
  if [ "$kind" = J ]; then
    path=$(jq -j -L "$JQLIB" "${LIB}"'sf_get("path"; "") | if type == "string" then . else error("path is not a string") end' <<<"$s" 2>/dev/null) || return 1
    case "$path" in /*) ;; *) path=$(hu_join "$root" "$path") ;; esac
    [ -f "$path" ] && [ -r "$path" ] || return 0
    # invalid UTF-8 crashes the Python mid-read; a BOM only spoils the first line
    iconv -f UTF-8 -t UTF-8 "$path" >/dev/null 2>&1 || return 1
    jq -R -n -c -L "$JQLIB" --argjson src "$s" "${LIB}"'
      ($src | sf_get("include"; null) | if truthy then . else {} end) as $inc
      | [inputs | pystrip | select(. != "" and (startswith("\ufeff") | not)) | (fromjson? // empty) | select(type == "object")
         | (if ($inc | type) != "object" then error("include is not an object") else . end)
         | select(($inc | length) == 0
                  or (sf_get(($inc | sf_get("field"; "") | key(.) | if type == "string" then . else "" end); "") | sf_pystr)
                     == ($inc | sf_get("equals"; "") | sf_pystr))
         | mapped($src)]' "$path" > "$W/items.json" 2>/dev/null || return 1
    return 0
  fi
  [ "$kind" = C ] || return 0
  tag=$(jq -j -L "$JQLIB" "${LIB}"'sf_get("command"; "") | if truthy | not then "E" elif type == "string" then "S" + . else "X" end' <<<"$s" 2>/dev/null) || return 1
  case "$tag" in E*) return 0 ;; S*) cmd=${tag#S} ;; *) return 1 ;; esac
  shlex_split "$cmd" || return 1
  # the timeout is read before an empty argv fails, as Python reads it inside the try
  t=$(hu_int "${INTAKE_SWEEP_CMD_TIMEOUT-15}" x); [ "$t" != x ] || return 0
  [ "${#SHLEX_ARGV[@]}" -gt 0 ] || return 1
  case "${SHLEX_ARGV[0]}" in /*) ;; */*) SHLEX_ARGV[0]=$(hu_join "$root" "${SHLEX_ARGV[0]}") ;; esac
  out="$W/cmd.out"
  ( cd "$root" 2>/dev/null && hu_run_capture "$t" "$out" "${SHLEX_ARGV[@]}" ); rc=$?
  [ "$rc" -eq 0 ] || return 0
  hu_utf8_ok "$out" || return 0
  jq -c -s 'if length == 1 and (.[0] | type) == "array" then .[0] else [] end' "$out" 2>/dev/null \
    | jq -c -L "$JQLIB" --argjson src "$s" "${LIB}"'[.[] | select(type == "object") | mapped($src)]' > "$W/items.json" 2>/dev/null || return 1
  return 0
}

if [ "$check" = 1 ]; then
  if [ "$count" -eq 0 ]; then
    echo "intake-sweep: no sources configured (looked in $root/_meta/intake-sources.json)"
    exit 0
  fi
  bad=0; i=0
  while [ "$i" -lt "$count" ]; do
    s=$(jq -c ".[$i]" <<<"$sources"); i=$((i + 1))
    if [ "$(jq -r 'type' <<<"$s")" != object ]; then
      echo "  ?  (malformed source entry, not an object)"; bad=$((bad + 1)); continue
    fi
    source_info "$s" || exit 0
    if [ "$KNOWN" = N ]; then
      echo "  FAIL $NAME: unknown kind '$KIND' (expected: command/jsonl)"; bad=$((bad + 1)); continue
    fi
    read_source "$s" || exit 0
    stats=$(jq -r '"\(length) \(map(select(.title | test("[^\\s\\x1c-\\x1f]"))) | length) \(map(select(.url | test("[^\\s\\x1c-\\x1f]"))) | length)"' "$W/items.json")
    set -- $stats
    if [ "$1" -gt 0 ]; then status="ok  "; else status="WARN"; bad=$((bad + 1)); fi
    echo "  $status $NAME ($KIND): $1 item(s), $2 titled, $3 with url"
  done
  echo "intake-sweep check: $count source(s), $bad needing attention"
  exit 0
fi

[ "$count" -gt 0 ] || exit 0

default_state=~/.claude/dwarves-kit/state/intake-sweep
state_dir="${INTAKE_SWEEP_STATE_DIR-$default_state}"
state_path() { printf '%s' "${state_dir:+$state_dir/}$1"; }

# Throttle: a sweep ran within INTAKE_SWEEP_MIN_INTERVAL seconds. Bookkeeping errors never block.
if [ "$force" = 0 ]; then
  hu_throttled "$state_dir" last-run "$(hu_int "${INTAKE_SWEEP_MIN_INTERVAL-86400}" 86400)" && exit 0
fi

backlog="${BACKLOG_STAGE_BACKLOG-$(hu_join "$root" _meta/BACKLOG.md)}"
staging="${BACKLOG_STAGE_STAGING-$(hu_join "$root" _meta/backlog-staging.md)}"
swept_file=$(state_path swept-keys.txt)
# The board and the staging file are read whole: one that exists but cannot be read, or is not
# UTF-8, crashes the Python.
for f in "$backlog" "$staging"; do
  if [ -f "$f" ] && { [ ! -r "$f" ] || ! iconv -f UTF-8 -t UTF-8 "$f" >/dev/null 2>&1; }; then exit 0; fi
done
readable() { [ -f "$1" ] && [ -r "$1" ] && printf '%s' "$1" || printf '/dev/null'; }

# Read every source, in order. An unknown kind warns on stderr and is skipped; a crash shape stages nothing.
: > "$W/batch.ndjson"; i=0
while [ "$i" -lt "$count" ]; do
  s=$(jq -c ".[$i]" <<<"$sources"); i=$((i + 1))
  [ "$(jq -r 'type' <<<"$s")" = object ] || continue
  source_info "$s" || exit 0
  if [ "$KNOWN" = N ]; then
    echo "intake-sweep: source '$NAME' has unknown kind '$KIND' (expected: command/jsonl), skipped" >&2
    continue
  fi
  read_source "$s" || exit 0
  jq -c -L "$JQLIB" --argjson s "$s" --slurpfile items "$W/items.json" -n 'include "staging-format";
    if ($s | sf_get("name"; "?") | type) == "array" or ($s | sf_get("name"; "?") | type) == "object" then error("name") else . end
    | {name: ($s | sf_get("name"; "?") | sf_pystr), u: ($s | sf_get("u"; "lo")), f: ($s | sf_get("f"; "hi")), home: ($s | sf_get("home"; "")), items: $items[0]}' >> "$W/batch.ndjson" 2>/dev/null || exit 0
done

date=$(date +%Y-%m-%d)
res=$(jq -c -n -L "$JQLIB" --slurpfile batch "$W/batch.ndjson" --arg date "$date" \
  --rawfile backlog "$(readable "$backlog")" --rawfile staging "$(readable "$staging")" --rawfile swept "$(readable "$swept_file")" \
  'include "staging-format";
   (($backlog | sf_board_keys) + ($staging | sf_staging_keys) | map({(.): true}) | add // {}) as $titles0
   | (($backlog | sf_universal) + ($staging | sf_universal)) as $text
   | ($swept | sf_splitlines | map({(.): true}) | add // {}) as $swept0
   | reduce $batch[] as $src ({titles: $titles0, swept: $swept0, blocks: [], keys: [], counts: {}};
       reduce $src.items[] as $c (. + {n: 0};
         ($c.title | sf_norm) as $nt
         | (if $c.url != "" then $c.url else $nt end) as $key
         | if $key == "" or .swept[$key] or .titles[$nt] or ($c.url != "" and ($text | contains($c.url))) then .
           else ({title: $c.title, intent: (if $c.intent != "" then $c.intent else $c.url end),
                  approach: (if $c.url != "" then $c.url else "(no url)" end),
                  u: $src.u, f: $src.f, home: $src.home, source: "intake-sweep \($src.name) \($date)"} | sf_render) as $b
                | if $b == null then .
                  else .blocks += [$b] | .keys += [$key] | .swept[$key] = true | .titles[$nt] = true | .n += 1 end
           end)
       | .counts[$src.name] = .n | del(.n))
   | {blocks, keys, per: ([.counts | to_entries[] | select(.value > 0) | "\(.key): \(.value)"] | join(", "))}' 2>/dev/null) || exit 0

nblocks=$(jq '.blocks | length' <<<"$res")
[ "$nblocks" -gt 0 ] || exit 0

# Append the blocks (a header first when the file is new), then record the keys. A staging path
# with no directory part, or one that cannot be written, stages nothing and records nothing.
case "$staging" in */*) ;; *) exit 0 ;; esac
header=""
[ -f "$staging" ] || header=$'# Backlog staging (auto, via backlog-stage)\n\nCandidates auto-extracted from sessions. Review + promote by hand.\nGitignored: may name unfiled work. NEVER the source of truth.\n\n'
text=$(jq -j '.blocks | join("")' <<<"$res"; printf x)
# the one locked staging write path (lib/reflect/staging-format.sh -> staging-format.py append)
printf '%s' "${text%x}" | sf_append "$staging" "$header" || exit 0
{ mkdir -p "$state_dir" && jq -r '.keys[]' <<<"$res" >> "$swept_file"; } 2>/dev/null || true
printf '\xf0\x9f\xa7\xb2 intake-sweep: staged %s candidate(s) (%s) in %s.\n' "$nblocks" "$(jq -r '.per' <<<"$res")" "$staging"
exit 0
