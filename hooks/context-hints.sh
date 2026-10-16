#!/bin/bash
# context-hints.sh -- UserPromptSubmit hook that injects temporal and keyword skill hints into the prompt context.
# Function-named port of ops-toolkit's cc-context-hooks (kit-foldin design note, was
# cc-context-hooks). Two cheap string additions, printed to stdout (UserPromptSubmit
# injects stdout as context); silent when there is nothing to add:
#
#   temporal    "Session time: <elapsed> elapsed, <idle> since your last prompt." from a tiny
#               per-session {start, last} state file; past 6 h elapsed it adds a cache-hygiene
#               nudge (/clear or /dcompact). The first prompt of a session adds nothing.
#   skill-hint  "Maybe-relevant skills: <skill> (keyword: <kw>)" for every keyword in a JSON
#               map {"keyword": "skill-or-command"} found in the prompt as a whole word,
#               case-insensitive. The shipped map is EMPTY (a consumer's skills are unknown
#               to the kit); a consumer points CONTEXT_HINTS_SKILLMAP at its own.
#
# Coexists with the SessionStart context-readiness.sh (different event, different purpose).
# Behavior pinned against the Python original by tests/test-context-hints-parity.sh.
#
# Env (the last three mainly make tests deterministic):
#   CONTEXT_HINTS_SKILLMAP=FILE  keyword -> skill JSON (default: context-hints-skills-map.json beside this hook)
#   CONTEXT_HINTS_STATE=DIR      per-session timing state (default ~/.claude/dwarves-kit/state/context-hints)
#   CONTEXT_HINTS_NOW=EPOCH      override "now"
#   CONTEXT_HINTS_TEMPORAL=0     turn the temporal line off
# Exit 0 always: a context hint never blocks a prompt. Any malformed input, state, or map
# makes the hook print nothing (the Python swallowed those crashes the same way).

set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "context-hints: jq not found; hints are off" >&2; exit 0; }

# The kit dir this hook really lives in (a symlinked hook still finds its map).
src="${BASH_SOURCE[0]}"
while [ -h "$src" ]; do
  dir=$(cd -P "$(dirname "$src")" && pwd)
  src=$(readlink "$src")
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
HERE=$(cd -P "$(dirname "$src")" && pwd)

INPUT=$(cat) || exit 0
# A BOM before the JSON is a parse error to Python's json.load, so it is one here. A lone high
# surrogate escape (an emoji cut in half) is a parse error to jq but not to Python: swap it for
# U+FFFD and parse again.
case "$INPUT" in $'\xef\xbb\xbf'*) exit 0 ;; esac
if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  INPUT=$(printf '%s' "$INPUT" | jq -Rrs 'gsub("\\\\u[dD][89abAB][0-9a-fA-F]{2}(?!\\\\u[dD][c-fC-F])"; "\\ufffd")' 2>/dev/null) || exit 0
fi

# Python truthiness, as the original's `or` chains used it.
FUNCS='
def truthy: . != null and . != false and . != 0 and . != "" and . != [] and . != {};
def pystr: if type == "string" then . elif . == null then "None" elif . == true then "True"
  elif . == false then "False" elif type == "number" then tostring else "?" end;
'

# Session id: session_id, else sessionId, else "default"; one to 64 of [A-Za-z0-9_-] or it
# is "default", so a payload can never steer the state path. The output ends in an x so a
# trailing newline survives command substitution. stdin must be one JSON object.
sid=$(printf '%s' "$INPUT" | jq -rnj "$FUNCS"'
  (input) as $o
  | if ([inputs] | length) > 0 then error elif ($o | type) != "object" then error else
    (if ($o.session_id | truthy) then $o.session_id
     elif ($o.sessionId | truthy) then $o.sessionId else "default" end | pystr) as $s
    | (if ($s | test("^[A-Za-z0-9_-]{1,64}$")) then $s else "default" end), "x" end' 2>/dev/null) || exit 0
sid=${sid%x}

default_state=~/.claude/dwarves-kit/state/context-hints
state_dir="${CONTEXT_HINTS_STATE-$default_state}"
state_path="${state_dir:+$state_dir/}$sid.json"
map_path="${CONTEXT_HINTS_SKILLMAP-$HERE/context-hints-skills-map.json}"
# A file that is missing, unreadable, or starts with a BOM (a parse error to Python) reads as
# empty, which the program treats as invalid JSON.
usable() { [ -f "$1" ] && [ -r "$1" ] && [ "$(head -c 3 "$1" | od -An -tx1 | tr -d ' \n')" != efbbbf ]; }
state_file=$state_path; map_file=$map_path
usable "$state_file" || state_file=/dev/null
usable "$map_file" || map_file=/dev/null

# One program for the whole decision. It prints the state to write, a separator, a Y or N
# for "print something", the text, and a closing x. Crash points of the Python (a state file
# that is not an object, a prompt that is not a string, a map that is not an object) print
# nothing, and a crash after the state write keeps that write, as the Python did.
res=$(printf '%s' "$INPUT" | jq -rj --rawfile state "$state_file" --rawfile map "$map_file" \
  --arg now "${CONTEXT_HINTS_NOW-}" --arg off "${CONTEXT_HINTS_TEMPORAL-}" "$FUNCS"'
def toint: if . < 0 then 0 - ((0 - .) | floor) else floor end;
def pad2: tostring | ("0" + .)[-2:];
def humanize: toint as $s
  | if $s < 60 then "\($s)s"
    elif $s < 3600 then "\($s / 60 | floor)m\($s % 60 | pad2)s"
    else "\($s / 3600 | floor)h\(($s % 3600) / 60 | floor | pad2)m" end;
def pyfloat: if type == "number" then .
  elif type == "boolean" then (if . then 1 else 0 end)
  elif type == "string" then (try (gsub("^\\s+|\\s+$"; "") | tonumber) catch "VALUE") else "TYPE" end;
def reescape: gsub("(?<c>[\\\\^$.|?*+()\\[\\]{}])"; "\\" + .c);
# The Python \b: a boundary between a word character (a letter, a digit, or _) and anything else.
# The Oniguruma \b also counts combining marks as word characters, so a decomposed accent differs,
# and its lookbehind refuses a case-insensitive match. So find every place the key occurs (a
# zero-width match, so overlapping ones count), then test the characters either side by hand.
def isw($cp): $cp != null and ([$cp] | implode | test("^[\\p{L}\\p{N}_]$"));
def keyword_hit($prompt; $cps; $k):
  any($prompt | match("(?=(" + ($k | reescape) + "))"; "gi");
      .offset as $o | ($o + ($k | length)) as $e
      | (isw(if $o == 0 then null else $cps[$o - 1] end) != isw($cps[$o]))
        and (isw(if $e == 0 then null else $cps[$e - 1] end) != isw($cps[$e])));

def temporal:
  if $off == "0" then {ok: true, write: null, line: null}
  else
    (if $now == "" then now else (try ($now | gsub("^\\s+|\\s+$"; "") | tonumber) catch null) end) as $t
    | if $t == null then {ok: false}
      else
        (try [$state | fromjson] catch null) as $parsed
        | (if $parsed == null then {start: $t, last: $t}
           elif ($parsed[0] | type) != "object" then {crash: true}
           else
             ($parsed[0] | if has("start") then .start else $t end | pyfloat) as $a
             | if $a == "TYPE" then {crash: true}
               elif $a == "VALUE" then {start: $t, last: $t}
               else
                 ($parsed[0] | if has("last") then .last else $t end | pyfloat) as $b
                 | if $b == "TYPE" then {crash: true}
                   elif $b == "VALUE" then {start: $t, last: $t}
                   else {start: $a, last: $b} end
               end
           end) as $st
        | if $st.crash then {ok: false}
          else
            ($t - $st.start) as $elapsed | ($t - $st.last) as $idle
            | {ok: true, write: ({start: $st.start, last: $t} | tojson),
               line: (if $elapsed < 1 then null
                      else "Session time: \($elapsed | humanize) elapsed, \($idle | humanize) since your last prompt."
                           + (if $elapsed > 21600 then "\nconsider /clear or /dcompact (cache-hygiene rule)" else "" end) end)}
          end
      end
  end;

. as $o
| temporal as $tp
| if ($tp.ok | not) then "\u0001N" else
    ($o.prompt | if truthy then . else ($o.lastPrompt | if truthy then . else "" end) end) as $prompt
    | (if ($prompt | type) != "string" then {crash: true}
       elif ($prompt | test("\\S")) | not then {hints: []}
       else
         ($prompt | explode) as $cps
         | (try [$map | fromjson] catch null) as $m
         | if $m == null then {hints: []}
           elif ($m[0] | type) != "object" then {crash: true}
           else {hints: [$m[0] | to_entries[]
                 | select(.key as $k | keyword_hit($prompt; $cps; $k))
                 | "\(.value | pystr) (keyword: \(.key))"]} end
       end) as $h
    | if $h.crash then ($tp.write // ""), "\u0001N"
      else ([$tp.line | select(. != null)]
            + (if ($h.hints | length) > 0 then ["Maybe-relevant skills: " + ($h.hints | join("; "))] else [] end)) as $lines
        | ($tp.write // ""), "\u0001", (if ($lines | length) > 0 then "Y" + ($lines | join("\n")) else "N" end)
      end
  end, "x"' 2>/dev/null) || exit 0

res=${res%x}
write=${res%%$'\001'*}
rest=${res#*$'\001'}
if [ -n "$write" ]; then
  { mkdir -p "$state_dir" && printf '%s' "$write" >| "$state_path"; } 2>/dev/null || true
fi
case "$rest" in Y*) printf '%s\n' "${rest#Y}" ;; esac
exit 0
