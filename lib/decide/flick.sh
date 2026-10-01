#!/usr/bin/env bash
# flick.sh -- the decide subsystem engine: answer "pick one of N" questions through a decision
# API in about half a second, so a kit step can replace a 20 to 60 s in-session judgment.
#
# kit-verb: flick | pick one of N through a decision API; shadow-only, fails open, always exit 0
#
# Usage:
#   flick [decide] < request.json   one JSON object on stdout: backend, model, latency_ms, mode,
#                                   answers, error, counts. Exit 0 on every path.
#   flick body < request.json       the provider request body the egress guard lets through.
#                                   No network, no token. For tests and audits.
#   flick --help                    this text
#
# A command-layer tool. Hooks never call it (the hook budget and the no-LLM-in-hooks rule),
# and a test pins that. Config is read root-only (kit-config.sh kit_config_get_root): the
# [decide] block names a credential source and authorizes egress, so a project .kit.toml
# must not set it. Contract and rationale: docs/specs/SPEC-381-flick.md.
set -u

FLICK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Derived from this script's own path, never the cwd: a repo the operator happens to stand in
# must not be able to widen the public-name allowlist.
KIT_ROOT="$(cd "$FLICK_DIR/../.." && pwd)"

[ -n "${FLICK_DEBUG:-}" ] || exec 2>/dev/null

# ---- fail-open envelope ------------------------------------------------------------------------
# The EXIT trap is the guarantee: whatever breaks below, the caller gets valid JSON and exit 0.
EMITTED=0
FALLBACK_JSON='{"backend":"","model":"","latency_ms":0,"mode":"shadow","answers":{},"error":"bad_input","counts":{"answered":0,"denied":0,"error":0}}'
_flick_exit() { [ "$EMITTED" = 1 ] || printf '%s\n' "$FALLBACK_JSON"; exit 0; }
trap _flick_exit EXIT
trap 'exit 0' HUP INT TERM

usage() { sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; EMITTED=1; exit 0; }

# Output state, set as the run learns it.
BACKEND=""; MODEL=""; LATENCY_MS=0; MODE_OUT="shadow"
NORM=""; PARSED=0; DENIED=0; KEEP=""; DENY_IDX=""

# Nothing parsed, so nothing to count. The error comes from the closed set, never from input.
fail_input() {
  local out
  out="$(jq -nc --arg err "${1:-bad_input}" '{backend:"",model:"",latency_ms:0,mode:"shadow",answers:{},error:$err,counts:{answered:0,denied:0,error:0}}')" || exit 0
  [ -n "$out" ] || exit 0
  printf '%s\n' "$out"; EMITTED=1; exit 0
}

# A whole-call failure after parsing: no answers; every parsed question the guard did not
# deny counts as error (denied ones stay denied).
fail_all() {
  local out
  out="$(jq -nc --arg backend "$BACKEND" --arg model "$MODEL" --argjson lat "${LATENCY_MS:-0}" \
    --arg mode "$MODE_OUT" --arg err "$1" --argjson p "$PARSED" --argjson d "$DENIED" \
    '{backend:$backend,model:$model,latency_ms:$lat,mode:$mode,answers:{},error:$err,counts:{answered:0,denied:$d,error:($p-$d)}}')" || exit 0
  [ -n "$out" ] || exit 0
  printf '%s\n' "$out"; EMITTED=1; exit 0
}

# ---- config ------------------------------------------------------------------------------------
# Root-only read: operator kit.toml, else kit-root kit.toml, else the default. The project
# .kit.toml is never opened. One builtin pass over each file replaces ten kit_config_get_root
# calls (one awk exec each): a process spawn is the dominant cost on a hardened macOS host.
# Same rules as lib/config/kit-config.sh _kit_toml_get: section header, '#' comments, one layer
# of double quotes, first match wins, an empty value counts as unset.
if [ -f "$KIT_ROOT/lib/config/kit-config.sh" ]; then . "$KIT_ROOT/lib/config/kit-config.sh" 2>/dev/null || true; fi

# load_decide_block <file> <prefix>: set <prefix>_<key> for every [decide] key found.
load_decide_block() {
  local file="$1" pre="$2" line sec="" h k v
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] || continue
    if [ "${line:0:1}" = "[" ]; then h="${line//[][]/}"; sec="${h//[[:space:]]/}"; continue; fi
    [ "$sec" = decide ] || continue
    case "$line" in *=*) ;; *) continue ;; esac
    k="${line%%=*}"; k="${k//[[:space:]]/}"
    case "$k" in backend|mode|timeout_ms|points|jev_model|openai_model|jev_token_env|openai_token_env|allow_names|deny_words) ;; *) continue ;; esac
    v="${line#*=}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
    v="${v#\"}"; v="${v%\"}"
    local seen="SEEN_${pre}_${k}"
    [ -z "${!seen:-}" ] || continue
    printf -v "$seen" '%s' 1
    printf -v "${pre}_${k}" '%s' "$v"
  done < "$file"
}

# cfgget <key> <default>: operator value, else kit-root value, else the default.
cfgget() {
  local op="OP_$1" rt="RT_$1"
  if [ -n "${!op:-}" ]; then printf '%s' "${!op}"; return; fi
  if [ -n "${!rt:-}" ]; then printf '%s' "${!rt}"; return; fi
  printf '%s' "$2"
}

load_config() {
  local v op_file rt_file
  op_file="$(kit_config_operator 2>/dev/null)"; rt_file="$(kit_config_root 2>/dev/null)"
  load_decide_block "$op_file" OP
  load_decide_block "$rt_file" RT
  CFG_BACKEND="$(cfgget backend none)"
  case "$CFG_BACKEND" in none|jev|openai) ;; *) CFG_BACKEND=none ;; esac
  CFG_MODE="$(cfgget mode shadow)"
  case "$CFG_MODE" in shadow|decide) ;; *) CFG_MODE=shadow ;; esac
  v="$(cfgget timeout_ms 1500)"
  case "$v" in ''|*[!0-9]*) v=1500 ;; esac
  [ "${#v}" -le 6 ] || v=10000
  # Floor 1500 (the vendor trial's security screen), ceiling 10000 so a typo cannot hang a wrap.
  [ "$v" -ge 1500 ] || v=1500
  [ "$v" -le 10000 ] || v=10000
  CFG_TIMEOUT_MS="$v"
  CFG_POINTS="$(cfgget points "")"
  CFG_JEV_MODEL="$(cfgget jev_model jev-1.13.0)"
  [[ "$CFG_JEV_MODEL" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || CFG_JEV_MODEL=jev-1.13.0
  CFG_JEV_TOKEN_ENV="$(cfgget jev_token_env JEV_API_TOKEN)"
  CFG_OPENAI_MODEL="$(cfgget openai_model "")"
  CFG_ALLOW_NAMES="$(cfgget allow_names "")"
  CFG_DENY_WORDS="$(cfgget deny_words "")"
}

point_enabled() { # <point>: exact word match in the space-separated list, no globbing
  local p found=1
  set -f
  for p in $CFG_POINTS; do [ "$p" = "$1" ] && found=0; done
  set +f
  return $found
}

# ---- the decision point registry ---------------------------------------------------------------
# A point is a closed entry: its slots, its template, its choices and their criteria text. A
# caller supplies slots, never question text, and per-choice text comes only from here. A new
# point needs its own spec.
POINT_WRAP_7B_STATE='A kit workflow step is deciding whether work it is about to build duplicates an existing tool. Each question names one existing tool and one candidate job, by name only.'
POINT_WRAP_7B_CRITERIA='{"enhance":"The existing tool already covers, or partly covers, the job of the candidate, so the candidate should extend it.","new":"The existing tool is unrelated to the job of the candidate, so the candidate is new work.","none":"The two names give no basis to decide."}'
RS=$'\037'

# ---- input -------------------------------------------------------------------------------------
# Stage one: shape and character checks only. It prints, one per line: the normalized request as
# compact JSON, the point, then one record per question (id, candidate, hit, existing) joined by
# the ASCII unit separator, which no accepted value can hold (control characters are refused).
PARSE_PROG='
  def ctl: explode | any(.[]; . < 32 or . == 127);
  def okstr: type == "string" and length <= 200 and (ctl | not);
  if type == "object" and ((keys - ["point","questions"]) == [])
     and (.point | okstr) and (.questions | type == "array")
     and ((.questions | length) >= 1 and (.questions | length) <= 50)
     and all(.questions[];
           type == "object" and ((keys - ["id","candidate","hit","existing"]) == [])
           and has("id") and has("candidate") and has("hit")
           and (.id | type == "string" and test("\\A[A-Za-z0-9_-]{1,40}\\z"))
           and (.candidate | okstr) and (.hit | okstr)
           and ((has("existing") | not) or (.existing | okstr)))
     and (([.questions[].id] | length) == ([.questions[].id] | unique | length))
  then (tojson, .point, (.questions[] | [.id, .candidate, .hit, (.existing // "")] | join("\u001f")))
  else error("bad_input") end'

# ---- the egress guard --------------------------------------------------------------------------
# PUBLIC is the space-delimited set of names this kit publishes, read from the kit root that
# holds THIS script, plus the operator's allow_names. A hit passes by whole-name equality only.
build_public() {
  local f n w
  PUBLIC=" "
  for f in "$KIT_ROOT"/bin/*; do [ -e "$f" ] || continue; n="${f##*/}"; PUBLIC="$PUBLIC$n "; done
  for f in "$KIT_ROOT"/commands/*.md "$KIT_ROOT"/agents/*.md; do [ -e "$f" ] || continue; n="${f##*/}"; PUBLIC="$PUBLIC${n%.md} "; done
  for f in "$KIT_ROOT"/skills/*/; do [ -d "$f" ] || continue; f="${f%/}"; PUBLIC="$PUBLIC${f##*/} "; done
  set -f
  for w in $CFG_ALLOW_NAMES; do PUBLIC="$PUBLIC$w "; done
  set +f
}

# guard_ok <candidate> <hit>: exit 0 when the pair may leave the host (wrap-7b rules).
guard_ok() {
  local cand="$1" hit="$2" w re_cand='^[a-z0-9-]{3,40}$' re_hit='^[A-Za-z0-9._-]{1,64}$' bad=0
  [[ "$cand" =~ $re_cand ]] || return 1
  [[ "$hit" =~ $re_hit ]] || return 1
  # deny_words: case-folded substring, so a word errs toward denial. Folding happens in the
  # match itself, with no extra process.
  shopt -s nocasematch
  set -f
  for w in $CFG_DENY_WORDS; do
    if [[ "$cand" == *"$w"* ]]; then bad=1; break; fi
  done
  set +f
  shopt -u nocasematch
  [ "$bad" = 0 ] || return 1
  case "$PUBLIC" in *" $hit "*) return 0 ;; esac
  return 1
}

# BODY_PROG: the provider request body for the questions the guard kept. The question text is
# REBUILT from the template and the matched slots; nothing the caller typed is forwarded.
BODY_PROG='
  ($idx | split(" ") | map(select(. != "") | tonumber)) as $keep
  | [ .questions | to_entries[] | select(.key as $k | any($keep[]; . == $k)) | .value ] as $kept
  | { model: $model, state: $state,
      questions: ( [ range(0; ($kept | length)) as $i
                     | { key: ("q" + (($i + 1) | tostring)),
                         value: { type: "choice", criteria: $criteria,
                                  instructions: ("Does the existing tool " + $kept[$i].hit + " cover the job of the candidate " + $kept[$i].candidate + "?") } } ]
                   | from_entries ) }'

# ---- main --------------------------------------------------------------------------------------
main() {
  local verb="${1:-decide}"
  case "$verb" in
    -h|--help|help) usage ;;
    decide|body) ;;
    *) fail_input bad_input ;;
  esac

  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' '{"backend":"","model":"","latency_ms":0,"mode":"shadow","answers":{},"error":"missing_dep","counts":{"answered":0,"denied":0,"error":0}}'
    EMITTED=1; exit 0
  fi

  load_config

  # A test-only URL override: honoured only for a loopback http URL with no userinfo.
  FLICK_URL_OK=""
  if [ -n "${FLICK_URL:-}" ]; then
    local re='^http://(127\.0\.0\.1|localhost)(:[0-9]+)?(/|$)'
    case "$FLICK_URL" in *[[:space:][:cntrl:]]*) fail_input bad_input ;; esac
    [[ "$FLICK_URL" =~ $re ]] || fail_input bad_input
    FLICK_URL_OK="$FLICK_URL"
  fi

  local input parsed point line n=0 id cand hit ex
  IFS= read -r -d '' input || true
  [ "${#input}" -le 262144 ] || fail_input bad_input
  parsed="$(printf '%s' "$input" | jq -r "$PARSE_PROG" 2>/dev/null)" || fail_input bad_input
  Q_CAND=(); Q_HIT=()
  while IFS= read -r line; do
    case "$n" in
      0) NORM="$line" ;;
      1) point="$line" ;;
      *) IFS="$RS" read -r id cand hit ex <<<"$line"; Q_CAND[$((n-2))]="$cand"; Q_HIT[$((n-2))]="$hit" ;;
    esac
    n=$((n+1))
  done <<<"$parsed"
  PARSED=$((n-2))
  [ "$PARSED" -ge 1 ] || fail_input bad_input
  [ "$point" = "wrap-7b" ] || fail_input bad_input

  BACKEND="$CFG_BACKEND"
  [ "$BACKEND" != none ] || fail_all backend_none
  point_enabled "$point" || fail_all point_disabled
  if [ "$BACKEND" = openai ]; then MODEL="$CFG_OPENAI_MODEL"; fail_all unsupported; fi
  MODEL="$CFG_JEV_MODEL"
  [ "$CFG_MODE" != decide ] || MODE_NOTE=1

  # Guard: drop every denied question BEFORE any body exists.
  build_public
  local i=0
  while [ "$i" -lt "$PARSED" ]; do
    if guard_ok "${Q_CAND[$i]}" "${Q_HIT[$i]}"; then KEEP="$KEEP $i"; else DENY_IDX="$DENY_IDX $i"; DENIED=$((DENIED+1)); fi
    i=$((i+1))
  done
  [ -n "$KEEP" ] || fail_all egress_denied

  local body
  body="$(printf '%s' "$NORM" | jq -c --arg idx "${KEEP# }" --arg model "$MODEL" \
    --arg state "$POINT_WRAP_7B_STATE" --argjson criteria "$POINT_WRAP_7B_CRITERIA" "$BODY_PROG")" || fail_all bad_input
  if [ "$verb" = body ]; then printf '%s\n' "$body"; EMITTED=1; exit 0; fi

  command -v curl >/dev/null 2>&1 || fail_all missing_dep

  [[ "$CFG_JEV_TOKEN_ENV" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fail_all no_token
  local token="${!CFG_JEV_TOKEN_ENV:-}"
  [ -n "$token" ] || fail_all no_token
  case "$token" in *[[:cntrl:]\"\\]*) fail_all no_token ;; esac

  fail_all network
}

main "$@"
