#!/bin/bash
# harvest.sh -- hook that stages session learnings on PreCompact (no flag) and a LAB_LOG draft on SessionEnd (--lab-log); always exits 0.
# Function-named port of ops-toolkit's cc-harvest (kit-foldin design note, was cc-harvest). When a
# session is about to compact (or ends), the durable decisions, gotchas, and concepts in it are
# easy to lose. This reads the transcript, asks a cheap Claude model (Haiku) for the genuinely
# durable learnings, dedups them against the existing ledger and glossary files, and appends ONLY
# the new ones to a ledger as `queued`. It NEVER writes a durable home: the manual flush stays the
# gate, harvest auto-STAGES and a human flushes. The transcript is already in an Anthropic session,
# so Haiku adds no new data EXPOSURE, but a `claude -p` call does consume plan QUOTA.
#
# The LLM call sits behind HARVEST_EXTRACTOR (a command that reads the prompt on stdin and writes a
# JSON array on stdout; split like Python's shlex, never through a shell), so the dedup, append, and
# guard logic is testable without a model. Default: `claude -p --model haiku --setting-sources
# project`. The `--setting-sources project` is load-bearing: it stops the spawned extractor from
# loading the USER settings.json, where this hook lives, so it cannot re-fire the hook and recurse.
#
# Modes (a flag on argv; the first match in this order wins):
#   --cleanup [LEDGER]        human-run: archive every `flushed:*` row of a ledger to a sibling archive
#   --flush-list              the queued rows of every sweep ledger as one JSON array
#   --mark-flushed ROW REF    flip one sweep-ledger row from queued to flushed:<REF>
#   --lab-log                 SessionEnd: draft a session-close LAB_LOG entry to a staging file
#   --stop-trigger            Stop: every Nth turn, run the harvest (opt-in, HARVEST_STOP_TRIGGER)
#   (no flag)                 PreCompact / SessionEnd: stage ledger learnings
#   --sweep --dry-run --status the scheduled sweep (hooks/harvest_sweep.py)
#   --harvest-run F, --lab-log-run F, --stop-harvest F   the detached children of the three hook modes
# --cleanup, --flush-list, --mark-flushed, and the sweep verbs run in Python (hooks/harvest_sweep.py):
# they share per-ledger fcntl locks with the sweep. Every other mode runs here, in bash and jq.
#
# Sweep gate: the AUTO modes (no flag, --lab-log, --stop-trigger) exit 0 without running when either
#   * HARVEST_SWEEP_CHILD=1: the process tree is the sweep's own extractor, which must never
#     re-fire the hook (recursion guard);
#   * the sweep is ACTIVE on this host (its <state>/sweep/installed marker exists AND
#     harvest.enable resolves true) AND harvest.hook_when_sweep_on is false, so a session is never
#     staged or paid for twice while the sweep reads it.
# [harvest] keys resolve through kit_config_get_root only: a project config file rides inside an
# untrusted PR and can neither switch the sweep on nor keep the hook running. Explicit verbs are
# never gated: they are operator actions, not hook fires.
#
# The hook returns almost at once. `claude -p` can take 120 s, and PreCompact, SessionEnd, and Stop
# give a hook 30 s, so the default path hands the work to a detached child (its own process group)
# that outlives the hook. HARVEST_SYNC=1 runs it inline (tests).
#
# Env:
#   HARVEST_LEDGER=FILE        ledger to append to (default <repo-root>/_meta/learned-ledger.md)
#   HARVEST_GLOSSARIES=A:B     extra dedup sources (default <repo-root>/learning/*/GLOSSARY.md)
#   HARVEST_EXTRACTOR=CMD      override the LLM call
#   HARVEST_FUZZY_THRESHOLD=N  also drop a candidate within Levenshtein distance N of a known slug (default 0 = off)
#   HARVEST_MAXCHARS=N         transcript characters sent to the model (default 12000)
#   HARVEST_LABLOG_DRAFT=FILE  --lab-log staging file (default <repo-root>/_meta/.lab-log-draft.md)
#   HARVEST_STOP_TRIGGER=1     enable --stop-trigger (default off); HARVEST_STOP_N=N fires every N turns (default 10)
#   HARVEST_STOP_SYNC=1        run a --stop-trigger fire inline
#   HARVEST_STATE_DIR=DIR      debounce stamps, turn counters, locks, and the children's payload files
#   HARVEST_MIN_INTERVAL=S     at most one no-flag and one --lab-log harvest per S seconds (default 3600); 0 turns it off
#   HARVEST_SYNC=1             run the no-flag and --lab-log harvests inline
#   REPO_ROOT=DIR              consumer seam for the repo-relative defaults above
# Exit 0 always: a harvest never blocks a compaction, a session end, or a stop. Behavior is pinned
# against the Python original by tests/test-harvest-parity.sh; a shape the Python crashed on stages
# nothing.

set -uo pipefail

src="${BASH_SOURCE[0]}"
while [ -h "$src" ]; do
  dir=$(cd -P "$(dirname "$src")" && pwd)
  src=$(readlink "$src")
  case "$src" in /*) ;; *) src="$dir/$src" ;; esac
done
HERE=$(cd -P "$(dirname "$src")" && pwd)
SELF="$HERE/$(basename "$src")"

argv_has() { local f=$1 a; shift; for a in "$@"; do [ "$a" = "$f" ] && return 0; done; return 1; }
arg_after() { # arg_after <flag> <args...>: the argument after the first <flag>, or empty
  local flag=$1 a seen=0; shift
  for a in "$@"; do
    if [ "$seen" = 1 ]; then printf '%s' "$a"; return 0; fi
    [ "$a" = "$flag" ] && seen=1
  done
  return 0
}

_auto=1
for a in "$@"; do
  case "$a" in
    --lab-log|--stop-trigger) ;;
    *) _auto=0 ;;
  esac
done
default_state=~/.claude/dwarves-kit/state/harvest
if [ "$_auto" = 1 ]; then
  if [ "${HARVEST_SWEEP_CHILD:-}" = "1" ]; then
    exit 0
  fi
  _state="${HARVEST_STATE_DIR:-$default_state}"
  if [ -f "$_state/sweep/installed" ]; then
    # shellcheck source=../lib/config/kit-config.sh
    source "$HERE/../lib/config/kit-config.sh"
    _en="$(kit_config_get_root harvest.enable false | tr 'A-Z' 'a-z')"
    _hook="$(kit_config_get_root harvest.hook_when_sweep_on false | tr 'A-Z' 'a-z')"
    case "$_en" in
      true|1|yes|on)
        case "$_hook" in true|1|yes|on) ;; *) exit 0 ;; esac ;;
    esac
  fi
fi

# The operator verbs and the sweep verbs run in the sweep module, the first match in the old dispatcher's order.
if argv_has --cleanup "$@" || argv_has --flush-list "$@" || argv_has --mark-flushed "$@"; then
  python3 "$HERE/harvest_sweep.py" "$@" || true
  exit 0
fi
if ! argv_has --lab-log-run "$@" && ! argv_has --lab-log "$@" && ! argv_has --stop-trigger "$@" \
   && ! argv_has --stop-harvest "$@" && ! argv_has --harvest-run "$@" \
   && { argv_has --sweep "$@" || argv_has --dry-run "$@" || argv_has --status "$@"; }; then
  python3 "$HERE/harvest_sweep.py" "$@" || true
  exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "harvest: jq not found; the harvest is off" >&2; exit 0; }
JQLIB="$HERE/../lib/reflect"
# shellcheck source=../lib/reflect/shlex-split.sh
source "$JQLIB/shlex-split.sh"
# shellcheck source=../lib/reflect/hook-util.sh
source "$JQLIB/hook-util.sh"
# shellcheck source=../lib/telemetry/egress-fail.sh
source "$HERE/../lib/telemetry/egress-fail.sh"

W=$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX") || exit 0
trap 'case "$W" in /*/*) command rm -rf -- "$W" ;; esac 2>/dev/null' EXIT

LIB='include "staging-format";
def truthy: . != null and . != false and . != 0 and . != "" and . != [] and . != {};
def pystrip: gsub("^[\\s\\x1c-\\x1f]+|[\\s\\x1c-\\x1f]+$"; "");
def slugify: sf_pystr | ascii_downcase | gsub("[^a-z0-9]+"; "-") | sub("^-+"; "") | sub("-+$"; "") | .[0:60];
'
PROMPT_HEAD='You extract durable, reusable learnings from a coding/ops session transcript.
Output ONLY a JSON array, no prose. Each element:
  {"item": "<short-kebab-slug>", "kind": "concept|insight|decision", "home": "til|research|glossary|drop", "why": "<one sentence>"}
Include ONLY genuinely durable, non-obvious learnings worth keeping later. Exclude chit-chat, transient state, and anything obvious. If there is nothing worth keeping, output []. Transcript follows:

'
PROMPT_LABLOG_HEAD='You draft ONE concise LAB_LOG entry for a coding/ops session, from the transcript.
Format EXACTLY:
## DATE - <short-kebab-slug>: <one-line what>
then 3 to 8 single-line bullets. Rules: the log is an INDEX, not the record; no narrative arcs; do not restate commit messages; point at durable storage (PR #s / SPECs / files). If the session has nothing worth logging, output exactly: NONE.
Transcript follows:

'

state_dir="${HARVEST_STATE_DIR-$default_state}"
state_path() { printf '%s' "${state_dir:+$state_dir/}$1"; }
truthy_env() { local v; v=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'); case "$v" in 1|true|yes|on) return 0 ;; esac; return 1; }
readable() { [ -f "$1" ] && [ -r "$1" ] && printf '%s' "$1" || printf '/dev/null'; }

if [ -n "${REPO_ROOT:-}" ]; then
  root=$REPO_ROOT
else
  root=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$root" ] || root=$(pwd -P)
fi
today=$(date +%Y-%m-%d)

# path_ok <path>: a default write target under the repo root must not sit behind a symlink, or the
# append lands in whatever file the link names. A HARVEST_* override outside the root is the
# operator's own choice and passes. Without the guard library nothing under the root is written.
if source "$HERE/../lib/config/safe-path.sh" 2>/dev/null; then
  path_ok() { case "$1" in "$root"/*) kit_refuse_symlink_path "$root" "$1" 2>/dev/null ;; esac; }
else
  path_ok() { case "$1" in "$root"/*) return 1 ;; esac; }
fi

# lock_run <try|wait> <lock-file> <command...>: run a command under an exclusive flock. Returns 75
# when "try" finds the lock held. flock(1) where it exists (Linux), lockf(1) on macOS; both use
# flock(2), so they exclude the Python processes that take the same lock. With neither, the
# command runs unlocked.
lock_run() {
  local mode=$1 lf=$2; shift 2
  if command -v flock >/dev/null 2>&1; then
    if [ "$mode" = try ]; then flock -n -E 75 "$lf" "$@"; else flock "$lf" "$@"; fi
  elif command -v lockf >/dev/null 2>&1; then
    if [ "$mode" = try ]; then lockf -k -t 0 "$lf" "$@"; else lockf -k "$lf" "$@"; fi
  else
    "$@"
  fi
}

# detach <mode-flag> <payload-json>: write the payload to the state dir and start `<mode-flag> <file>`
# in the background in its own process group. Returns 0 when it started.
detach() {
  local flag=$1 payload=$2 pf
  pf="$(state_path "payload-${flag#--}-$$.json")"
  { mkdir -p "$state_dir" && printf '%s' "$payload" > "$pf"; } 2>/dev/null || return 1
  set -m
  nohup bash "$SELF" "$flag" "$pf" </dev/null >/dev/null 2>&1 &
  set +m
  return 0
}

# debounced <key>: return 0 when the <key> harvest ran within HARVEST_MIN_INTERVAL seconds (skip it),
# else stamp it with the epoch and return 1. Bookkeeping errors never block.
debounced() {
  local interval stamp m
  interval=$(hu_int "${HARVEST_MIN_INTERVAL-3600}" 3600)
  [ "$interval" -gt 0 ] || return 1
  mkdir -p "$state_dir" 2>/dev/null || return 1
  stamp=$(state_path "last-$1")
  if [ -e "$stamp" ]; then
    m=$(hu_mtime "$stamp") && [ $(( $(date +%s) - m )) -lt "$interval" ] && return 0
  fi
  printf '%s' "$(date +%s)" > "$stamp" 2>/dev/null
  return 1
}

# read_input: stdin as one JSON object (a BOM or a lone high surrogate handled as in the other ports).
# Sets PAYLOAD to the compact JSON, or {} when stdin is not JSON, as the Python's read_payload does.
# A JSON value that is not an object is a crash shape: PAYLOAD_CRASH=1.
read_input() {
  local raw; raw=$(cat) || raw=""
  PAYLOAD='{}'; PAYLOAD_CRASH=0
  case "$raw" in $'\xef\xbb\xbf'*) return 0 ;; esac
  if ! printf '%s' "$raw" | jq -e . >/dev/null 2>&1; then
    raw=$(printf '%s' "$raw" | jq -Rrs 'gsub("\\\\u[dD][89abAB][0-9a-fA-F]{2}(?!\\\\u[dD][c-fC-F])"; "\\ufffd")' 2>/dev/null) || return 0
  fi
  PAYLOAD=$(printf '%s' "$raw" | jq -s -c 'if length == 1 then .[0] else {"__invalid": true} end' 2>/dev/null) || { PAYLOAD='{}'; return 0; }
  case "$PAYLOAD" in '{"__invalid":true}') PAYLOAD='{}'; return 0 ;; esac
  [ "$(jq -r 'type' <<<"$PAYLOAD")" = object ] || PAYLOAD_CRASH=1
  return 0
}

# payload_tp <payload-json>: the truthy string transcript_path; nothing when absent or falsy; an error status for a crash shape
payload_tp() { jq -j -L "$JQLIB" "$LIB"'if type == "object" then (sf_get("transcript_path"; null) | if truthy then (if type == "string" then . else error("path") end) else empty end) else error("payload") end' <<<"$1" 2>/dev/null; }

# transcript_text <path> <max>: the text blocks of every user and assistant entry, newline-joined, the
# last <max> characters kept, followed by an x sentinel; nothing when a crash shape is met (invalid
# UTF-8, a line that is not an object, a message that is not an object, a non-string text block).
# The parse itself lives in lib/session/parse_transcript.py (--harvest-text), the one transcript parser.
transcript_text() {
  [ -f "$1" ] && [ -r "$1" ] || return 0
  python3 "$HERE/../lib/session/parse_transcript.py" --harvest-text "$2" "$1" 2>/dev/null || return 0
}

# run_extractor <prompt-file> <out-file>: the extractor with the prompt on stdin, a 120 s timeout,
# stdout kept whatever the exit status. Returns 1 on a command string shlex refuses. A failed,
# timed-out, or empty call stays fail-open but leaves one line in the egress-failures ledger.
run_extractor() {
  local cmd="${HARVEST_EXTRACTOR:-claude -p --model haiku --setting-sources project}" rc=0
  shlex_split "$cmd" || return 1
  : > "$2"
  [ "${#SHLEX_ARGV[@]}" -gt 0 ] || return 1
  HU_STDIN="$1" hu_run_capture 120 "$2" "${SHLEX_ARGV[@]}" || rc=$?
  if [ -e "$2.timedout" ]; then   # subprocess.run throws a timed-out command's stdout away
    : > "$2"; egress_fail harvest "timeout after 120s"
  elif [ "$rc" -ne 0 ]; then
    egress_fail harvest "extractor exit $rc"
  elif ! grep -q '[^[:space:]]' "$2" 2>/dev/null; then
    egress_fail harvest "empty output"
  fi
  return 0
}

# the first balanced [...] of the model output, counting brackets with no regard for JSON strings
FIRST_ARRAY='. as $t | ($t | explode) as $c | ($c | index(91)) as $s
  | if $s == null then []
    else (reduce range($s; $c | length) as $i ({d: 0, e: null};
            if .e != null then . elif $c[$i] == 91 then .d += 1
            elif $c[$i] == 93 then (.d -= 1 | if .d == 0 then .e = $i else . end) else . end)) as $r
         | if $r.e == null then []
           else (try ($c[$s:$r.e + 1] | implode | fromjson) catch []) | if type == "array" then . else [] end end
    end'

# prepare <payload-json> <head> <out-prompt-file> <max>: the transcript text behind <head>, written to a
# prompt file. Returns 1 when there is nothing to send (no path, no readable transcript, no text, or a crash shape).
prepare() {
  local tp text
  tp=$(payload_tp "$1") || return 1
  [ -n "$tp" ] || return 1
  text=$(transcript_text "$tp" "$4"); [ -n "$text" ] || return 1
  text=${text%x}
  printf '%s' "$text" | jq -R -s -e 'test("\\S")' >/dev/null 2>&1 || return 1
  printf '%s%s' "$2" "$text" > "$3"
}

# stage_locked <candidates-file> <ledger> <glossaries-file> <fuzzy>: the dedup and the append, run with
# the ledger's lock held (lock_run executes this through `--stage-locked`). Prints the fresh row count.
stage_locked() {
  local cand=$1 ledger=$2 gl=$3 fuzzy=$4 known="$W/known" tsv="$W/cand.tsv" fresh header g
  # the Python reads the ledger and every glossary as text: invalid UTF-8 in one ends the run before anything is appended
  if [ -f "$ledger" ] && ! iconv -f UTF-8 -t UTF-8 "$ledger" >/dev/null 2>&1; then return 1; fi
  { if [ -f "$ledger" ]; then
      jq -r -R -s -L "$JQLIB" "$LIB"'
        sf_universal | split("\n")[] | split("|") | map(pystrip) | select(length >= 4 and (.[1] | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))) | (.[2] | slugify)' "$ledger" 2>/dev/null || return 1
    fi
    while IFS= read -r g; do
      [ -f "$g" ] || continue
      iconv -f UTF-8 -t UTF-8 "$g" >/dev/null 2>&1 || return 1
      jq -r -R -s -L "$JQLIB" "$LIB"'
        sf_universal | split("\n")[] | capture("^#{2,4}\\s+(?<t>.+)")? | .t | slugify' "$g" 2>/dev/null || return 1
    done < "$gl"; } > "$known"
  jq -r -L "$JQLIB" "$LIB"'
    .[] | select(type == "object")
    | [(sf_get("item"; "") | slugify),
       (sf_get("kind"; null) | if IN("concept", "insight", "decision") then . else "insight" end),
       (sf_get("home"; null) | if IN("til", "research", "glossary", "drop") then . else "drop" end)] | @tsv' "$cand" > "$tsv" 2>/dev/null || return 1
  fresh=$(awk -F'\t' -v fuzzy="$fuzzy" '
    function lev(a, b,   n, m, i, j, c, x, y, z, v, prev, cur) {
      if (a == b) return 0
      n = length(a); m = length(b)
      if (n == 0) return m
      if (m == 0) return n
      for (j = 0; j <= m; j++) prev[j] = j
      for (i = 1; i <= n; i++) {
        cur[0] = i
        for (j = 1; j <= m; j++) {
          c = (substr(a, i, 1) == substr(b, j, 1)) ? 0 : 1
          x = prev[j] + 1; y = cur[j - 1] + 1; z = prev[j - 1] + c
          v = x; if (y < v) v = y; if (z < v) v = z
          cur[j] = v
        }
        for (j = 0; j <= m; j++) prev[j] = cur[j]
      }
      return prev[m]
    }
    FILENAME == ARGV[1] { K[$0] = 1; KL[++nk] = $0; next }
    {
      slug = $1
      if (slug == "" || (slug in K) || (slug in S)) next
      if (fuzzy > 0) {
        dup = 0
        for (i = 1; i <= nk && !dup; i++) if (lev(slug, KL[i]) <= fuzzy) dup = 1
        for (i = 1; i <= ns && !dup; i++) if (lev(slug, SL[i]) <= fuzzy) dup = 1
        if (dup) next
      }
      S[slug] = 1; SL[++ns] = slug
      print
    }' "$known" "$tsv")
  if [ -n "$fresh" ]; then
    header=""
    [ -e "$ledger" ] || header=$'| date | item | kind | home | status |\n|---|---|---|---|---|\n'
    { printf '%s' "$header"; printf '%s\n' "$fresh" | awk -F'\t' -v d="$today" '{ printf "| %s | %s | %s | %s | queued |\n", d, $1, $2, $3 }'; } 2>/dev/null >> "$ledger" || return 1
    printf '%s\n' "$fresh" | grep -c ''
  else
    echo 0
  fi
}

# stage_candidates <candidates-file> <ledger>: dedup against the ledger and the glossaries, append the
# fresh rows, print their count. The ledger's lock is held for the read and the append, so concurrent
# harvests serialize instead of racing (observed as up to 6x duplicates). Returns 1 on a crash shape.
stage_candidates() {
  local cand=$1 ledger=$2 gl="$W/glossaries" fuzzy g ledger_dir
  fuzzy=$(hu_int "${HARVEST_FUZZY_THRESHOLD-0}" 0); [ "$fuzzy" -ge 0 ] || fuzzy=0
  if [ -n "${HARVEST_GLOSSARIES:-}" ]; then
    printf '%s\n' "$HARVEST_GLOSSARIES" | tr ':' '\n' > "$gl"
  else
    for g in "$root"/learning/*/GLOSSARY.md; do [ -e "$g" ] && printf '%s\n' "$g"; done > "$gl"
  fi
  case "$ledger" in */*) ;; *) return 1 ;; esac
  path_ok "$ledger" && path_ok "$ledger.lock" || return 1
  ledger_dir=${ledger%/*}; [ -n "$ledger_dir" ] || ledger_dir=/
  mkdir -p "$ledger_dir" 2>/dev/null || return 1
  : >> "$ledger.lock" 2>/dev/null || return 1
  lock_run wait "$ledger.lock" bash "$SELF" --stage-locked "$cand" "$ledger" "$gl" "$fuzzy"
}

# harvest_payload <payload-json>: the core no-flag harvest.
harvest_payload() {
  local max pf of cand ledger n total
  max=$(hu_int "${HARVEST_MAXCHARS-12000}" x); [ "$max" != x ] || return 0
  pf="$W/prompt"; of="$W/out"; cand="$W/cand.json"
  prepare "$1" "$PROMPT_HEAD" "$pf" "$max" || return 0
  run_extractor "$pf" "$of" || return 0
  iconv -f UTF-8 -t UTF-8 "$of" >/dev/null 2>&1 || return 0
  jq -R -s -c "$FIRST_ARRAY" "$of" > "$cand" 2>/dev/null || return 0
  [ "$(cat "$cand")" != '[]' ] || return 0
  ledger="${HARVEST_LEDGER-$(hu_join "$root" _meta/learned-ledger.md)}"
  n=$(stage_candidates "$cand" "$ledger") || return 0
  total=$(jq 'length' "$cand")
  echo "harvest: staged $n new (of $total extracted) -> $ledger" >&2
  return 0
}

# run_harvest_locked <payload-json>: the single-flight guard shared by the stop-trigger fire and the
# detached harvest children: a harvest already in flight makes this one skip.
run_harvest_locked() {
  local lock rc
  lock="$(state_path harvest.lock)"
  { : > "$lock"; } 2>/dev/null || return 0
  printf '%s' "$1" > "$W/locked-payload"
  lock_run try "$lock" bash "$SELF" --do-harvest "$W/locked-payload"; rc=$?
  if [ "$rc" = 75 ]; then echo "harvest: stop-trigger skip (harvest already in flight)" >&2; fi
  return 0
}

# lab_log <payload-json>: draft a session-close LAB_LOG entry to a staging file (never LAB_LOG.md).
lab_log() {
  local max pf of block draft draft_dir
  max=$(hu_int "${HARVEST_MAXCHARS-12000}" x); [ "$max" != x ] || return 0
  pf="$W/prompt"; of="$W/out"
  prepare "$1" "${PROMPT_LABLOG_HEAD/DATE/$today}" "$pf" "$max" || return 0
  run_extractor "$pf" "$of" || return 0
  iconv -f UTF-8 -t UTF-8 "$of" >/dev/null 2>&1 || return 0
  block=$(jq -R -s -j '
    gsub("^[\\s\\x1c-\\x1f]+|[\\s\\x1c-\\x1f]+$"; "") as $raw
    | if $raw == "" or ($raw | ascii_upcase | startswith("NONE")) then empty
      else ($raw | gsub("\r\n|[\r\u000b\u000c\u001c-\u001e\u0085  ]"; "\n") | split("\n")
            | map(select((gsub("^[\\s\\x1c-\\x1f]+"; "") | startswith("```")) | not)) | join("\n")
            | gsub("^[\\s\\x1c-\\x1f]+|[\\s\\x1c-\\x1f]+$"; "")) as $b
        | if ($b | test("(?m)^##\\s+[0-9]{4}-[0-9]{2}-[0-9]{2}")) then $b, "x" else empty end
      end' "$of" 2>/dev/null)
  if [ -z "$block" ]; then
    echo "harvest: no LAB_LOG draft (nothing worth logging)" >&2
    return 0
  fi
  block=${block%x}
  draft="${HARVEST_LABLOG_DRAFT-$(hu_join "$root" _meta/.lab-log-draft.md)}"
  case "$draft" in */*) ;; *) return 0 ;; esac
  path_ok "$draft" || return 0
  draft_dir=${draft%/*}; [ -n "$draft_dir" ] || draft_dir=/
  { mkdir -p "$draft_dir" && printf '<!-- staged %s by harvest --lab-log; review, then move into LAB_LOG.md -->\n%s\n\n' "$today" "$block" >> "$draft"; } 2>/dev/null || return 0
  echo "harvest: staged a LAB_LOG draft -> $draft (review; not auto-committed)" >&2
  return 0
}

# --- internal entry points: the locked bodies ---
case "${1:-}" in
  --stage-locked) stage_locked "$2" "$3" "$4" "$5"; exit $? ;;
  --do-harvest) harvest_payload "$(cat "$2" 2>/dev/null)"; exit 0 ;;
esac

# --- the detached children: read the handed-off payload, run, always remove the payload file ---
for mode in --lab-log-run --stop-harvest --harvest-run; do
  if argv_has "$mode" "$@"; then
    pf=$(arg_after "$mode" "$@")
    if [ -n "$pf" ] && [ -f "$pf" ]; then
      payload=$(jq -c . "$pf" 2>/dev/null)
      if [ -n "$payload" ]; then
        case "$mode" in
          --lab-log-run) lab_log "$payload" ;;
          *) run_harvest_locked "$payload" ;;
        esac
      fi
      { rm -f "$pf"; } 2>/dev/null
    fi
    exit 0
  fi
done

# --- --lab-log ---
if argv_has --lab-log "$@"; then
  debounced lablog && exit 0
  read_input
  [ "$PAYLOAD_CRASH" = 0 ] || exit 0
  tp=$(payload_tp "$PAYLOAD") || exit 0
  [ -n "$tp" ] || exit 0
  if truthy_env "${HARVEST_SYNC:-}"; then lab_log "$PAYLOAD"; exit 0; fi
  detach --lab-log-run "$PAYLOAD" && echo "harvest: --lab-log fired detached (draft lands after this hook returns)" >&2
  exit 0
fi

# --- --stop-trigger: a per-N-turns nudge cadence (opt-in, single-flight, never blocks the turn) ---
if argv_has --stop-trigger "$@"; then
  truthy_env "${HARVEST_STOP_TRIGGER:-}" || exit 0
  read_input
  n=$(hu_int "${HARVEST_STOP_N-10}" 10); [ "$n" -ge 1 ] || n=1
  mkdir -p "$(state_path turns)" 2>/dev/null || exit 0
  [ "$PAYLOAD_CRASH" = 0 ] || exit 0
  sid=$(jq -j 'if has("session_id") then .session_id else null end
               | if . == null or . == false or . == 0 or . == "" or . == [] or . == {} then ""
                 elif type == "string" then . elif type == "boolean" then "True" else tostring end
               | gsub("[^A-Za-z0-9._-]"; "_") | .[0:128]' <<<"$PAYLOAD")
  [ -n "$sid" ] || sid=nosession
  cfile="$(state_path "turns/$sid")"
  cur=$(hu_int "$(cat "$cfile" 2>/dev/null)" 0); cur=$((cur + 1))
  { printf '%s' "$cur" > "$cfile.tmp" && mv -f "$cfile.tmp" "$cfile"; } 2>/dev/null
  if [ $(( (cur % n + n) % n )) -ne 0 ]; then
    echo "harvest: stop-trigger skip (turn $cur, fires every $n)" >&2
    exit 0
  fi
  tp=$(payload_tp "$PAYLOAD") || exit 0
  [ -n "$tp" ] || exit 0
  if truthy_env "${HARVEST_STOP_SYNC:-}"; then run_harvest_locked "$PAYLOAD"; exit 0; fi
  detach --stop-harvest "$PAYLOAD" && echo "harvest: stop-trigger fire (detached harvest)" >&2
  exit 0
fi

# --- the default harvest (PreCompact, SessionEnd) ---
debounced ledger && exit 0
read_input
[ "$PAYLOAD_CRASH" = 0 ] || exit 0
tp=$(payload_tp "$PAYLOAD") || exit 0
[ -n "$tp" ] || exit 0
if truthy_env "${HARVEST_SYNC:-}"; then harvest_payload "$PAYLOAD"; exit 0; fi
detach --harvest-run "$PAYLOAD" && echo "harvest: fired detached (ledger lands after this hook returns)" >&2
exit 0
