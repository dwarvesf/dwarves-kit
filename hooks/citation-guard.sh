#!/usr/bin/env bash
# citation-guard.sh -- Stop hook. Every file:line citation in the final assistant
# message must resolve: the file exists and has at least that many lines. Fenced
# code, inline code, and URLs are stripped first so examples do not
# false-positive. Log-only by default (bad refs append to a log, exit 0);
# CITATION_GUARD_STRICT=1 blocks the stop (exit 2) so the model can fix the refs.
# Only the strict path exits non-zero; every other outcome fails open with empty
# stdout.
#
# Bash + jq port of the Python hook. jq does the text work: it streams the
# transcript line by line (a non-JSON line is skipped and reading continues) and
# its Oniguruma regex supplies the strip patterns plus the Unicode-aware \S and
# \b that POSIX grep/awk cannot express. Ref line numbers stay digit STRINGS end
# to end: jq numbers are doubles, so tonumber would corrupt a 20-digit number.
#
# Env:
#   CITATION_GUARD_STRICT=1   block the stop instead of log-only
#   CITATION_GUARD_ROOT=DIR   resolve relative refs under DIR (else payload cwd, else $PWD)
#   CITATION_GUARD_LOG=FILE   log path (default ~/.claude/dwarves-kit/logs/citation-guard.log)

set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "citation-guard: jq not found, skipping" >&2; exit 0; }

INPUT=$(cat)
# Exactly one JSON object, as json.load demands: the Python crashed on a
# non-object and rejected trailing data; the port just declines to act.
jq -se 'length == 1 and (.[0] | type) == "object"' <<<"$INPUT" >/dev/null 2>&1 || exit 0

tp=$(jq -r '.transcript_path | strings' <<<"$INPUT")
{ [ -n "$tp" ] && [ -r "$tp" ]; } || exit 0

# Walk the transcript once. A line that fails to parse is skipped; the shapes
# the Python crashed on (a non-object line, a truthy non-object message, a text
# block whose text is not a string) discard the whole result, since the crash
# meant nothing after that line counted. Otherwise the kept text is the
# newline-join of text blocks from the LAST assistant entry that has any.
text=$(jq -nRr '
  def truthy: . != null and . != false and . != 0 and . != "" and . != [] and . != {};
  # A lone high surrogate (\ud83d with no low half) fails fromjson; json.loads
  # accepts it, so swap it for U+FFFD and parse again before skipping the line.
  reduce (inputs | (fromjson? // (gsub("\\\\u[dD][89abAB][0-9a-fA-F]{2}(?!\\\\u[dD][c-fC-F])"; "\\ufffd") | fromjson?))) as $o ({t: "", ok: true};
    if .ok | not then .
    elif ($o | type) != "object" then .ok = false
    elif ($o.type // "") != "assistant" then .
    elif ($o.message | truthy) and (($o.message | type) != "object") then .ok = false
    else ($o.message | if truthy then . else {} end | .content) as $c
      | if ($c | type) != "array" then .
        else [$c[] | select(type == "object" and .type == "text")] as $tb
          | if ($tb | length) == 0 then .
            elif ([$tb[] | select(has("text") and (.text | type) != "string")] | length) > 0
            then .ok = false
            else .t = ([$tb[] | .text // ""] | join("\n"))
            end
        end
    end)
  | if .ok then .t else "" end' 2>/dev/null <"$tp") || exit 0
[ -n "$text" ] || exit 0

# Strip code and URLs, then emit deduped "path<TAB>line" refs in first-seen
# order. Leading zeros drop up front so 07 and 7 are one ref and print bare.
refs=$(printf '%s' "$text" | jq -Rsr '
  gsub("(?s)```.*?```"; "")
  | gsub("`[^`]*`"; "")
  | gsub("https?://\\S+"; "")
  | [scan("([A-Za-z0-9._/-]+\\.[A-Za-z0-9_]+):([0-9]+)\\b")
     | .[0] + "\t" + (.[1] | sub("^0+"; "") | sub("^$"; "0"))]
  | reduce .[] as $r ({o: [], s: {}};
      if .s[$r] then . else (.s[$r] = 1 | .o += [$r]) end)
  | .o[]' 2>/dev/null || true)
[ -n "$refs" ] || exit 0

# A truthy non-string cwd crashed the Python (exit 1, never a block); decline too.
jq -e '(.cwd | . == null or . == false or . == 0 or . == "" or . == [] or . == {} or type == "string")' <<<"$INPUT" >/dev/null 2>&1 || exit 0
root=${CITATION_GUARD_ROOT:-}
[ -n "$root" ] || root=$(jq -r '.cwd | strings' <<<"$INPUT")
[ -n "$root" ] || root=$PWD

bad=""
while IFS=$'\t' read -r path num; do
  [ -n "$path" ] || continue
  case $path in
    /*) target=$path ;;
    *)  target=$root/$path ;;
  esac
  if [ ! -f "$target" ]; then
    bad="${bad:+$bad; }$path:$num (no such file)"
    continue
  fi
  # jq -R yields one input per line and counts a trailing partial line, which
  # reproduces Python's line iteration without a wc + tail + od dance.
  if ! n=$(jq -Rn 'reduce inputs as $_ (0; . + 1)' 2>/dev/null <"$target"); then
    bad="${bad:+$bad; }$path:$num (unreadable)"
    continue
  fi
  # Digit-string compare: a longer string is a bigger integer, equal length
  # compares lexically. Handles numbers of any size.
  if [ "${#num}" -gt "${#n}" ] || { [ "${#num}" -eq "${#n}" ] && [[ $num > $n ]]; }; then
    bad="${bad:+$bad; }$path:$num (file has $n lines)"
  fi
done <<<"$refs"
[ -n "$bad" ] || exit 0

# CITATION_GUARD_LOG is taken verbatim when set (even empty); the default
# applies only when unset. A path without a slash has an empty dirname, where
# the Python's makedirs("") failed, so those write no log at all.
if [ "${CITATION_GUARD_LOG+x}" = x ]; then logp=$CITATION_GUARD_LOG
else logp=${HOME:-}/.claude/dwarves-kit/logs/citation-guard.log; fi
case $logp in
  */*)
    dir=${logp%/*}
    [ -n "$dir" ] || dir=/
    if mkdir -p "$dir" 2>/dev/null; then
      sid=$(jq -r '
        def truthy: . != null and . != false and . != 0 and . != "" and . != [] and . != {};
        if (.sessionId | truthy) then .sessionId
        elif (.session_id | truthy) then .session_id
        else "?" end' <<<"$INPUT")
      printf '%s\t%s\t%s\n' "$(date +%s)" "$sid" "$bad" 2>/dev/null >>"$logp" || true
    fi
    ;;
esac

if [ "${CITATION_GUARD_STRICT:-}" = "1" ]; then
  printf 'citation-guard: unresolved citations: %s\n' "$bad" >&2
  exit 2
fi
exit 0
