#!/bin/bash
# backlog-stage.sh -- SessionEnd hook that stages work-items from the session into a staging file, never onto the board.
# Function-named port of ops-toolkit's cc-backlog (kit-foldin design note, was cc-backlog). A
# harvest applied to a project board instead of a knowledge ledger: the action-items a user
# stated but did not file are easy to lose when a session ends. This reads the transcript, asks
# a cheap Claude model (Haiku) for the forward-looking work-items, dedups them against the live
# board and the staging buffer, and appends ONLY the new ones to a staging file as `[staged]`
# candidates. It NEVER writes the board: a human (or `board promote`) moves chosen candidates
# onto it. Propose, do not dispose.
#
# Opt-in, default off. A session ends with its follow-ups done or listed in its own report;
# staging candidates as a side effect filled a staging file nobody drained and fed a board that
# grew 13 to 25 rows a day. BACKLOG_STAGE_AUTO=1 (or true, yes, on) restores all three passes:
# the SessionEnd harvest, the SessionStart intake sweep, and the SessionStart count line.
#
# The LLM call sits behind BACKLOG_STAGE_EXTRACTOR (a command that reads the prompt on stdin and
# writes a JSON array on stdout; split like Python's shlex, never through a shell), so the dedup
# and append logic is testable without a model. Default: `claude -p --model haiku
# --setting-sources project`. The `--setting-sources project` is load-bearing: it stops the
# spawned extractor from loading the USER settings.json, where this hook lives, so it cannot
# re-fire SessionEnd and recurse.
#
# SessionEnd fires while the CLI is already tearing down, and the extractor can take 120 s, well
# past the hook's 30 s timeout. So the cheap local part (throttle, pre-filter) runs inline and the
# slow part (extractor, dedup, append) goes to a detached child (`--staged-run`, in its own
# process group) that outlives the hook. BACKLOG_STAGE_SYNC=1 runs it inline (tests).
#
# Consumer seam (no hardcoded tenant path): the board and staging file default repo-relative under
# `_meta/`, resolved from REPO_ROOT, else git's top level, else the cwd.
#
# Env:
#   BACKLOG_STAGE_BACKLOG=FILE    board to dedup against (default <repo-root>/_meta/BACKLOG.md)
#   BACKLOG_STAGE_STAGING=FILE    staging buffer (default <repo-root>/_meta/backlog-staging.md)
#   REPO_ROOT=DIR                 consumer seam for the two defaults above
#   BACKLOG_STAGE_EXTRACTOR=CMD   override the LLM call
#   BACKLOG_STAGE_MAXCHARS=N      transcript characters sent to the model (default 12000)
#   BACKLOG_STAGE_MIN_INTERVAL=S  at most one harvest per S seconds (default 3600); 0 turns it off
#   BACKLOG_STAGE_STATE_DIR=DIR   throttle stamp and the detached child's payload (default ~/.claude/dwarves-kit/state/backlog-stage)
#   BACKLOG_STAGE_PREFILTER=0     skip the forward-intent pre-filter (default on)
#   BACKLOG_STAGE_SYNC=1          run the extractor and the append inline, not detached
# Modes: no flag harvests the session; `--surface` (SessionStart) runs the intake sweep, then
# prints one line when candidates wait for review. Exit 0 always: a harvest never blocks a session
# end. Behavior is pinned against the Python original by tests/test-backlog-stage-parity.sh; a
# shape the Python crashed on stages nothing.

set -uo pipefail

case "${BACKLOG_STAGE_AUTO:-}" in 1|true|yes|on) ;; *) exit 0 ;; esac
command -v jq >/dev/null 2>&1 || { echo "backlog-stage: jq not found; the harvest is off" >&2; exit 0; }

src="${BASH_SOURCE[0]}"
while [ -h "$src" ]; do
  dir=$(cd -P "$(dirname "$src")" && pwd)
  src=$(readlink "$src")
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
HERE=$(cd -P "$(dirname "$src")" && pwd)
SELF="$HERE/$(basename "$src")"
JQLIB="$HERE/../lib/reflect"
# shellcheck source=../lib/reflect/shlex-split.sh
source "$JQLIB/shlex-split.sh"
# shellcheck source=../lib/reflect/hook-util.sh
source "$JQLIB/hook-util.sh"

# On the SessionStart surface pass, first sweep the consumer's declared deferred-link sources into
# the same staging funnel (config-gated, self-throttling), so the surfaced count already includes them.
case " $* " in *" --surface "*) bash "$HERE/intake-sweep.sh" || true ;; esac

if [ -n "${REPO_ROOT:-}" ]; then
  root=$REPO_ROOT
else
  root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$root" ] || root=$(pwd -P)
fi
backlog="${BACKLOG_STAGE_BACKLOG-$(hu_join "$root" _meta/BACKLOG.md)}"
staging="${BACKLOG_STAGE_STAGING-$(hu_join "$root" _meta/backlog-staging.md)}"

argv_has() { local f=$1 a; shift; for a in "$@"; do [ "$a" = "$f" ] && return 0; done; return 1; }
arg_after() { # arg_after <flag> <args...>: the argument after the first <flag>, or empty
  local flag=$1 a seen=0; shift
  for a in "$@"; do
    if [ "$seen" = 1 ]; then printf '%s' "$a"; return 0; fi
    [ "$a" = "$flag" ] && seen=1
  done
  return 0
}
truthy_env() { local v; v=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'); case "$v" in 1|true|yes|on) return 0 ;; esac; return 1; }

# --surface: one line when candidates wait. Fast and local, no model call.
for a in "$@"; do
  if [ "$a" = "--surface" ]; then
    [ -f "$staging" ] || exit 0
    iconv -f UTF-8 -t UTF-8 "$staging" >/dev/null 2>&1 || exit 0   # the Python reads it as text and crashes on invalid UTF-8
    n=$(LC_ALL=C tr '\r' '\n' < "$staging" 2>/dev/null | LC_ALL=C grep -c '^## \[staged\]')
    if [ "${n:-0}" -gt 0 ]; then
      s=s; [ "$n" = 1 ] && s=""
      printf '\xf0\x9f\x93\x8b %s backlog candidate%s staged in %s.\n' "$n" "$s" "$staging"
    fi
    exit 0
  fi
done

W=$(mktemp -d) || exit 0
trap 'case "$W" in /*/*) command rm -rf -- "$W" ;; esac 2>/dev/null' EXIT

LIB='include "staging-format";
def truthy: . != null and . != false and . != 0 and . != "" and . != [] and . != {};
def pystrip: gsub("^[\\s\\x1c-\\x1f]+|[\\s\\x1c-\\x1f]+$"; "");
'

PROMPT_HEAD='You extract FORWARD-LOOKING work-items from a coding/ops session transcript: things the user said they want to DO LATER but did not necessarily file yet.
Output ONLY a JSON array, no prose. Each element:
  {"title": "<short imperative title>", "intent": "<one sentence: the outcome wanted>", "approach": "<1-2 key steps or the open question>", "u": "hi|mid|lo", "f": "hi|mid|lo", "home": "<repo/tool guess or empty>"}
Include ONLY items with explicit forward intent (add to backlog, we should, let'"'"'s later, TODO, next time, remind me to, follow up). EXCLUDE: things already done this session, idle musings, questions, and anything already obviously tracked. If there is nothing, output []. u=urgency (cost of delay), f=feasibility (doable now). Transcript follows:

'

# run_extractor <prompt-file> <out-file>: the extractor command with the prompt on stdin and a 120 s
# timeout. Its stdout is kept whatever its exit status, but a timed-out run's stdout is thrown away,
# as subprocess.run does. Returns 1 on a command string shlex refuses or one that holds no command
# (both crash the Python).
run_extractor() {
  local cmd="${BACKLOG_STAGE_EXTRACTOR:-claude -p --model haiku --setting-sources project}"
  shlex_split "$cmd" || return 1
  [ "${#SHLEX_ARGV[@]}" -gt 0 ] || return 1
  : > "$2"
  HU_STDIN="$1" hu_run_capture 120 "$2" "${SHLEX_ARGV[@]}"
  [ ! -e "$2.timedout" ] || : > "$2"
  return 0
}

# stage_from_text <text-file> <date> <backlog> <staging>: the slow half. The extractor call, dedup
# against the board and the staging buffer, and the append. Returns 1 on a crash shape.
stage_from_text() {
  local textfile=$1 date=$2 bl=$3 st=$4 pf of arr res nblocks header out
  pf="$W/prompt"; of="$W/out"
  { printf '%s' "$PROMPT_HEAD"; cat "$textfile"; } > "$pf"
  run_extractor "$pf" "$of" || return 1
  iconv -f UTF-8 -t UTF-8 "$of" >/dev/null 2>&1 || return 1
  jq -L "$JQLIB" -R -s -c "$LIB"'
    # the first balanced [...] of the model output (tolerates fences and prose): count brackets
    # from the first "[" with no regard for strings, then parse that slice
    . as $t | ($t | explode) as $c | ($c | index(91)) as $s
    | if $s == null then []
      else (reduce range($s; $c | length) as $i ({d: 0, e: null};
              if .e != null then . elif $c[$i] == 91 then .d += 1
              elif $c[$i] == 93 then (.d -= 1 | if .d == 0 then .e = $i else . end) else . end)) as $r
           | if $r.e == null then []
             else (try ($c[$s:$r.e + 1] | implode | fromjson) catch []) | if type == "array" then . else [] end end
      end' "$of" > "$W/arr.json" 2>/dev/null || echo '[]' > "$W/arr.json"
  [ "$(cat "$W/arr.json")" != '[]' ] || return 0
  # the board and the staging file are read whole after the model call: one that exists but cannot
  # be read, or is not UTF-8, crashes the Python there
  for f in "$bl" "$st"; do
    if [ -f "$f" ] && { [ ! -r "$f" ] || ! iconv -f UTF-8 -t UTF-8 "$f" >/dev/null 2>&1; }; then return 1; fi
  done
  res=$(jq -n -c -L "$JQLIB" --slurpfile arr "$W/arr.json" --arg date "$date" \
    --rawfile bl "$(readable "$bl")" --rawfile st "$(readable "$st")" "$LIB"'
    (($bl | sf_board_keys_lines) + ($st | sf_staging_titles_lines) | map({(.): true}) | add // {}) as $known0
    | reduce $arr[0][] as $c ({known: $known0, blocks: []};
        if ($c | type) != "object" then .
        else ($c | sf_get("title"; "") | sf_norm) as $nt
          | if $nt == "" or .known[$nt] then .
            else (($c | {title: sf_get("title"; ""), intent: sf_get("intent"; ""), approach: sf_get("approach"; ""),
                         u: sf_get("u"; "lo"), f: sf_get("f"; "mid"), home: sf_get("home"; ""),
                         source: ("session " + ($date | sf_pystr))}) | sf_render) as $b
                 | if $b == null then . else .blocks += [$b] | .known[$nt] = true end
          end
        end)
    | .blocks' 2>/dev/null) || return 1
  nblocks=$(jq 'length' <<<"$res")
  [ "$nblocks" -gt 0 ] || return 0
  case "$st" in */*) ;; *) return 1 ;; esac
  local st_dir=${st%/*}; [ -n "$st_dir" ] || st_dir=/
  header=""
  [ -f "$st" ] || header=$'# Backlog staging (auto, via backlog-stage)\n\nCandidates auto-extracted from sessions. Review + promote by hand.\nGitignored: may name unfiled work. NEVER the source of truth.\n\n'
  out=$(jq -j 'join("")' <<<"$res"; printf x)
  { mkdir -p "$st_dir" && printf '%s%s' "$header" "${out%x}" >> "$st"; } 2>/dev/null || return 1
  return 0
}

readable() { [ -f "$1" ] && [ -r "$1" ] && printf '%s' "$1" || printf '/dev/null'; }

# --staged-run <payload-file> (anywhere in argv): the detached child. Reads the handed-off
# {text, date, backlog, staging}, stages, and always removes the payload file.
if argv_has --staged-run "$@"; then
  pf=$(arg_after --staged-run "$@")
  if [ -n "$pf" ] && [ -f "$pf" ]; then
    # all four keys must be present, as the Python indexes them before it calls anything; the
    # file is read as Python reads it (no BOM, valid UTF-8). Each field goes to its own file or
    # variable: the text can hold any byte a separator would be.
    if hu_utf8_ok "$pf" && jq -e -L "$JQLIB" 'type == "object" and has("text") and has("date") and has("backlog") and has("staging")
         and (.text | type) == "string" and (.backlog | type) == "string" and (.staging | type) == "string"' "$pf" >/dev/null 2>&1; then
      jq -j '.text' "$pf" > "$W/text"
      date=$(jq -j -L "$JQLIB" 'include "staging-format"; .date | sf_pystr' "$pf")
      bl=$(jq -j '.backlog' "$pf"; printf x); bl=${bl%x}
      st=$(jq -j '.staging' "$pf"; printf x); st=${st%x}
      stage_from_text "$W/text" "$date" "$bl" "$st" || true
    fi
    { rm -f "$pf"; } 2>/dev/null
  fi
  exit 0
fi

# ---- the SessionEnd harvest ----

INPUT=$(cat) || exit 0
case "$INPUT" in $'\xef\xbb\xbf'*) exit 0 ;; esac
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  INPUT=$(printf '%s' "$INPUT" | jq -Rrs 'gsub("\\\\u[dD][89abAB][0-9a-fA-F]{2}(?!\\\\u[dD][c-fC-F])"; "\\ufffd")' 2>/dev/null) || exit 0
fi
# stdin must be exactly one JSON object with a truthy string transcript_path; anything else is a no-op
fields=$(printf '%s' "$INPUT" | jq -L "$JQLIB" -rnj "$LIB"'
  (input) as $o
  | if ([inputs] | length) > 0 or ($o | type) != "object" then error
    else ($o | sf_get("transcript_path"; null)) as $tp
      | if ($tp | truthy | not) then error
        else (if ($tp | type) != "string" then "\u0002" else $tp end), "\u0001", (($o | sf_get("_today"; null)) | if truthy then sf_pystr else "" end), "x" end
    end' 2>/dev/null) || exit 0
fields=${fields%x}
tp=${fields%%$'\001'*}; today=${fields#*$'\001'}
# a truthy transcript_path that is not a string passes the throttle and then crashes the Python
badpath=0; [ "$tp" = $'\002' ] && badpath=1

default_state=~/.claude/dwarves-kit/state/backlog-stage
state_dir="${BACKLOG_STAGE_STATE_DIR-$default_state}"

hu_throttled "$state_dir" last-run "$(hu_int "${BACKLOG_STAGE_MIN_INTERVAL-3600}" 3600)" && exit 0

[ "$badpath" = 0 ] || exit 0
max=$(hu_int "${BACKLOG_STAGE_MAXCHARS-12000}" x); [ "$max" != x ] || exit 0

# The transcript text: the text blocks of every user and assistant entry, newline-joined, the
# last MAXCHARS characters kept. A shape the Python crashed on (invalid UTF-8, a line that is not
# an object, a message that is not an object, a non-string text block) ends the run with nothing
# staged.
[ -f "$tp" ] && [ -r "$tp" ] || exit 0
iconv -f UTF-8 -t UTF-8 "$tp" >/dev/null 2>&1 || exit 0
text=$(jq -L "$JQLIB" -R -n -j --argjson max "$max" "$LIB"'
  def blocks($o):
    ($o | sf_get("message"; null) | if truthy then . else {} end) as $m
    | if ($m | type) != "object" then error("message")
      else ($m | sf_get("content"; []) | if truthy then . else [] end) as $c
        | if ($c | type) == "array" then [$c[] | select(type == "object" and .type == "text" and (.text | truthy)) | .text]
          elif ($c | type) == "string" or ($c | type) == "object" then []
          else error("content") end
      end;
  (reduce (inputs | pystrip | select(. != "" and (startswith("\ufeff") | not))) as $line ({parts: [], bad: false};
     if .bad then .
     else (try [$line | fromjson] catch []) as $p
       | if ($p | length) == 0 then .
         elif ($p[0] | type) != "object" then .bad = true
         elif ($p[0].type | IN("user", "assistant")) then (try (.parts += blocks($p[0])) catch (.bad = true))
         else . end
     end)) as $r
  | if $r.bad or ([$r.parts[] | type != "string"] | any) then empty
    else ($r.parts | join("\n")) as $t
      | (if ($t | length) > $max then $t[(0 - $max):] else $t end), "x"
    end' "$tp" 2>/dev/null)
[ -n "$text" ] || exit 0
text=${text%x}
if ! printf '%s' "$text" | jq -R -s -e 'test("\\S")' >/dev/null 2>&1; then exit 0; fi

# Skip the model call on a session with no forward-intent signal (a deterministic gate).
if [ "${BACKLOG_STAGE_PREFILTER-1}" != "0" ]; then
  printf '%s' "$text" | jq -R -s -e 'test("\\b(?:to-?do|backlog|we should|i should|should we|let'"'"'?s\\b|next time|follow[- ]?up|remind me|reminder|need to|have to|going to|gonna|plan to|want to|in the future|revisit|circle back|action item|down the line|later on|come back to|for later)\\b"; "i")' >/dev/null 2>&1 || exit 0
fi

date=${today:-$(date +%Y-%m-%d)}
printf '%s' "$text" > "$W/text"

if truthy_env "${BACKLOG_STAGE_SYNC:-}"; then
  stage_from_text "$W/text" "$date" "$backlog" "$staging" || true
  exit 0
fi

# Detach: hand the work to a child in its own process group and return at once. The payload is
# built from files (the text can be megabytes) and moved into place only once it is whole.
pf="$state_dir/payload-$$.json"
if mkdir -p "$state_dir" 2>/dev/null \
   && jq -n -c --rawfile text "$W/text" --arg date "$date" --arg b "$backlog" --arg s "$staging" \
        '{text: $text, date: $date, backlog: $b, staging: $s}' > "$pf.tmp" 2>/dev/null \
   && mv -f "$pf.tmp" "$pf" 2>/dev/null; then
  # bash can print "child setpgid: Operation not permitted" when the child execs before the
  # parent sets its group; the group is set either way, so the shell's own message is dropped.
  { set -m; nohup bash "$SELF" --staged-run "$pf" </dev/null >/dev/null 2>&1 & set +m; } 2>/dev/null
  echo "backlog-stage: fired detached (candidates land in $staging after this hook returns)" >&2
else
  { command rm -f -- "$pf.tmp"; } 2>/dev/null
fi
exit 0
