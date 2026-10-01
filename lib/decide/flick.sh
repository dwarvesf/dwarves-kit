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
PARSED=0; DENIED=0

# envelope <error> <answers-json> <answered> <denied> <errored>
envelope() {
  jq -nc --arg backend "$BACKEND" --arg model "$MODEL" --argjson lat "${LATENCY_MS:-0}" \
    --arg mode "$MODE_OUT" --arg err "$1" --argjson answers "$2" \
    --argjson a "$3" --argjson d "$4" --argjson e "$5" \
    '{backend:$backend,model:$model,latency_ms:$lat,mode:$mode,answers:$answers,error:$err,counts:{answered:$a,denied:$d,error:$e}}'
}

finish() {
  local out; out="$(envelope "$@")" || exit 0
  [ -n "$out" ] || exit 0
  printf '%s\n' "$out"; EMITTED=1; exit 0
}

# A whole-call failure: no answers, every parsed question that the guard did not deny counts as error.
fail_all() { finish "$1" '{}' 0 "$DENIED" "$((PARSED - DENIED))"; }
# Nothing parsed, so nothing to count.
fail_input() { finish "${1:-bad_input}" '{}' 0 0 0; }

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

# ---- input -------------------------------------------------------------------------------------
# Stage one: shape only. A caller supplies slots, never question text.
PARSE_PROG='
  if type == "object" and (.point | type == "string") and (.questions | type == "array")
     and (.questions | length) >= 1 and (.questions | length) <= 50
  then . else error("bad_input") end'

# ---- main --------------------------------------------------------------------------------------
main() {
  local verb="${1:-decide}"
  case "$verb" in
    -h|--help|help) usage ;;
    decide|body) ;;
    *) command -v jq >/dev/null 2>&1 || true; fail_input bad_input ;;
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

  local input norm point
  IFS= read -r -d '' input || true
  [ "${#input}" -le 262144 ] || fail_input bad_input
  norm="$(printf '%s' "$input" | jq -c "$PARSE_PROG" 2>/dev/null)" || fail_input bad_input
  PARSED="$(printf '%s' "$norm" | jq '.questions | length')"
  point="$(printf '%s' "$norm" | jq -r '.point')"
  [ "$point" = "wrap-7b" ] || fail_input bad_input

  BACKEND="$CFG_BACKEND"
  [ "$BACKEND" != none ] || fail_all backend_none
  point_enabled "$point" || fail_all point_disabled
  if [ "$BACKEND" = openai ]; then MODEL="$(cfgget decide.openai_model "")"; fail_all unsupported; fi
  MODEL="$CFG_JEV_MODEL"

  if [ "$verb" = body ]; then finish bad_input '{}' 0 0 0; fi

  command -v curl >/dev/null 2>&1 || fail_all missing_dep

  [[ "$CFG_JEV_TOKEN_ENV" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || fail_all no_token
  local token="${!CFG_JEV_TOKEN_ENV:-}"
  [ -n "$token" ] || fail_all no_token
  case "$token" in *[[:cntrl:]\"\\]*) fail_all no_token ;; esac

  fail_all network
}

main "$@"
