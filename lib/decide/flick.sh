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
# must not set it. Contract and rationale: the flick spec under docs/specs/.
set -u

case "${BASH_SOURCE[0]}" in */*) FLICK_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)" ;; *) FLICK_DIR="$(pwd)" ;; esac
# Derived from this script's own path, never the cwd: a repo the operator happens to stand in
# must not be able to widen the public-name allowlist.
KIT_ROOT="$(cd "$FLICK_DIR/../.." && pwd)"

[ -n "${FLICK_DEBUG:-}" ] || exec 2>/dev/null

# ---- fail-open envelope ------------------------------------------------------------------------
# The EXIT trap is the guarantee: whatever breaks below, the caller gets valid JSON and exit 0.
EMITTED=0
FALLBACK_JSON='{"backend":"","model":"","latency_ms":0,"mode":"shadow","answers":{},"error":"bad_input","counts":{"answered":0,"denied":0,"error":0}}'
_flick_exit() { tok_cleanup 2>/dev/null; [ "$EMITTED" = 1 ] || printf '%s\n' "$FALLBACK_JSON"; exit 0; }
trap _flick_exit EXIT
trap 'exit 0' HUP INT TERM

usage() { sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; EMITTED=1; exit 0; }

# Output state, set as the run learns it.
BACKEND=""; MODEL=""; LATENCY_MS=0; MODE_OUT="shadow"
NORM=""; PARSED=0; DENIED=0; KEEP=""; DENY_IDX=""; DENY_REASON="guard"; WG_IDX=""; WG_REASON=word_gate

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
# Which files: exactly two, fixed by paths the operator owns, never by the caller's environment. A
# direnv .envrc or a project shell must not be able to point KIT_CONFIG_*, XDG_CONFIG_HOME or
# DWARVES_KIT at a file that switches the word gate off, edits deny_words, or names a token command.
# The kit root is this script's own root; the operator file is $HOME/.config/dwarves-kit/kit.toml.
# Only FLICK_TEST=1 (the same switch as FLICK_URL) honours KIT_CONFIG_OPERATOR and KIT_CONFIG_ROOT.
if [ "${FLICK_TEST:-}" = 1 ]; then
  KIT_CONFIG_OPERATOR="${KIT_CONFIG_OPERATOR:-${HOME:-}/.config/dwarves-kit}"
  KIT_CONFIG_ROOT="${KIT_CONFIG_ROOT:-$KIT_ROOT}"
else
  KIT_CONFIG_OPERATOR="${HOME:-}/.config/dwarves-kit"
  KIT_CONFIG_ROOT="$KIT_ROOT"
fi
export KIT_CONFIG_OPERATOR KIT_CONFIG_ROOT
# KIT_CONFIG_NO_PRIME: this hot path reads config with its own reader and a test pins its awk spawn count.
if [ -f "$KIT_ROOT/lib/config/kit-config.sh" ]; then KIT_CONFIG_NO_PRIME=1 . "$KIT_ROOT/lib/config/kit-config.sh" 2>/dev/null || true; fi

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
    case "$k" in backend|mode|timeout_ms|points|jev_model|openai_model|jev_token_env|jev_token_cmd|openai_token_env|openai_token_cmd|clef_model|clef_account|clef_token_env|clef_token_cmd|allow_names|deny_words|word_gate|dict_file) ;; *) continue ;; esac
    v="${line#*=}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
    v="${v#\"}"; v="${v%\"}"
    local seen="FLKC_SEEN_${pre}_${k}"
    [ -z "${!seen:-}" ] || continue
    printf -v "$seen" '%s' 1
    printf -v "${pre}_${k}" '%s' "$v"
  done < "$file"
}

# cfgget <key> <default>: operator value, else kit-root value, else the default.
cfgget() {
  local op="FLKC_OP_$1" rt="FLKC_RT_$1"
  if [ -n "${!op:-}" ]; then printf '%s' "${!op}"; return; fi
  if [ -n "${!rt:-}" ]; then printf '%s' "${!rt}"; return; fi
  printf '%s' "$2"
}

load_config() {
  local v op_file rt_file
  # The config variables live in one private namespace and are cleared first: an inherited
  # environment variable of that shape must never stand in for a config file.
  for v in $(compgen -v FLKC_); do unset "$v"; done
  op_file="$(kit_config_operator 2>/dev/null)"; rt_file="$(kit_config_root 2>/dev/null)"
  load_decide_block "$op_file" FLKC_OP
  load_decide_block "$rt_file" FLKC_RT
  CFG_BACKEND="$(cfgget backend none)"
  case "$CFG_BACKEND" in none|jev|openai|clef) ;; *) CFG_BACKEND=none ;; esac
  CFG_MODE="$(cfgget mode shadow)"
  case "$CFG_MODE" in shadow|decide) ;; *) CFG_MODE=shadow ;; esac
  # Clef is slower than Jev (p50 about 1.1 s, tail past 1.5 s), so its unset-timeout default
  # is 3000; an explicit timeout_ms always wins.
  local tdef=1500
  [ "$CFG_BACKEND" = clef ] && tdef=3000
  v="$(cfgget timeout_ms "$tdef")"
  case "$v" in ''|*[!0-9]*) v="$tdef" ;; esac
  [ "${#v}" -le 6 ] || v=10000
  # Floor 1500 (the vendor trial's security screen), ceiling 10000 so a typo cannot hang a wrap.
  [ "$v" -ge 1500 ] || v=1500
  [ "$v" -le 10000 ] || v=10000
  CFG_TIMEOUT_MS="$v"
  CFG_POINTS="$(cfgget points "")"
  CFG_JEV_MODEL="$(cfgget jev_model jev-1.13.0)"
  [[ "$CFG_JEV_MODEL" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || CFG_JEV_MODEL=jev-1.13.0
  CFG_JEV_TOKEN_ENV="$(cfgget jev_token_env JEV_API_TOKEN)"
  CFG_JEV_TOKEN_CMD="$(cfgget jev_token_cmd "")"
  CFG_OPENAI_MODEL="$(cfgget openai_model "")"
  CFG_CLEF_MODEL="$(cfgget clef_model clef)"
  case "$CFG_CLEF_MODEL" in clef|clef-flash) ;; *) CFG_CLEF_MODEL=clef ;; esac
  CFG_CLEF_ACCOUNT="$(cfgget clef_account "")"
  CFG_CLEF_TOKEN_ENV="$(cfgget clef_token_env FLICK_CLEF_TOKEN)"
  CFG_CLEF_TOKEN_CMD="$(cfgget clef_token_cmd "")"
  CFG_ALLOW_NAMES="$(cfgget allow_names "")"
  CFG_DENY_WORDS="$(cfgget deny_words "")"
  # Word gate: anything but an exact "off" is on, so a typo cannot open egress.
  CFG_WORD_GATE="$(cfgget word_gate on)"
  [ "$CFG_WORD_GATE" = off ] || CFG_WORD_GATE=on
  CFG_DICT_FILE="$(cfgget dict_file /usr/share/dict/words)"
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
POINT_WRAP_7B_STATE='A kit workflow step is deciding whether work it is about to build duplicates an existing tool. Each question names one existing tool, with its own public one-line description when known, and one candidate job by name only.'
POINT_WRAP_7B_CRITERIA='{"enhance":"The existing tool already does, or could own, the job of the candidate, so the candidate should extend that tool.","new":"The existing tool does an unrelated job, so the candidate is new work.","none":"The names and description give no basis to decide."}'
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

# ---- the word gate -----------------------------------------------------------------------------
# A deny list can never be complete, so the candidate slot also needs an allow rule: every
# hyphen segment of a candidate must be a dictionary word (case-insensitive, whole line), a
# built-in dev word, or a name the kit publishes (whole-name equality). Generic slugs are made of
# common words; a client or project name is not in any dictionary. The dictionary is read once per
# batch: one awk pass over every segment the other two sets did not already cover.
DEV_WORDS=" pr ci cd api cli json yaml toml md sql db git gh repo env url http https ssh tls jwt oauth sdk ui ux pdf csv tsv cron kv llm ai id ids sha diff lint todo wip config auth regex stdin stdout async "

dict_usable() {
  local size
  case "$CFG_DICT_FILE" in /*) ;; *) return 1 ;; esac
  [ -f "$CFG_DICT_FILE" ] && [ -r "$CFG_DICT_FILE" ] || return 1
  size="$(wc -c < "$CFG_DICT_FILE" 2>/dev/null)" || return 1
  size="${size//[[:space:]]/}"
  case "$size" in ''|*[!0-9]*) return 1 ;; esac
  [ "$size" -lt 16777216 ]
}

# word_gate_apply: drop every kept question whose candidate holds an unknown segment, or all of
# them when the dictionary is unusable (egress fails closed). Rewrites KEEP, DENY_IDX, DENIED.
word_gate_apply() {
  local k seg need="" matched="" rc=0 newkeep="" ok n
  [ "$CFG_WORD_GATE" = off ] && return 0
  # The dictionary must be an absolute path (never cwd-relative) to a readable regular file under 16 MB.
  if ! dict_usable; then
    WG_REASON=word_gate_no_dict
  else
    # A slug holds only [a-z0-9-] (guard_ok), so splitting on the hyphens by word splitting is safe.
    for k in $KEEP; do
      for seg in ${Q_CAND[$k]//-/ }; do
        case "$DEV_WORDS$PUBLIC" in *" $seg "*) continue ;; esac
        [ "${#seg}" -ge 3 ] || continue   # never a dictionary word: a dictionary lists every letter
        case " $need " in *" $seg "*) ;; *) need="$need$seg " ;; esac
      done
    done
    if [ -n "$need" ]; then
      # ponytail: awk, not `grep -Fixf`: BSD grep takes over 500 ms on a 236k-line dictionary, awk
      # about 100 ms. `look` (binary search) is faster still but needs a sorted file; add it as a
      # fast path if this overhead ever matters. No `LC_ALL=C` prefix on the awk call: with it,
      # macOS awk crashed (exit 139) on about 1 run in 10; a crash reads as word_gate_no_dict.
      matched="$(awk -v w="$need" 'BEGIN { n = split(w, a, " "); for (i = 1; i <= n; i++) want[a[i]] } { l = tolower($0); if (l in want) print l }' "$CFG_DICT_FILE" 2>/dev/null)" || rc=$?
      [ "$rc" = 0 ] || WG_REASON=word_gate_no_dict
    fi
  fi
  shopt -s nocasematch
  for k in $KEEP; do
    ok=1; n=0
    if [ "$WG_REASON" = word_gate_no_dict ]; then ok=0; else
      for seg in ${Q_CAND[$k]//-/ }; do
        n=$((n+1))
        case "$DEV_WORDS$PUBLIC" in *" $seg "*) continue ;; esac
        [[ $'\n'"$matched"$'\n' == *$'\n'"$seg"$'\n'* ]] || { ok=0; break; }
      done
      [ "$n" -gt 0 ] || ok=0   # "---" has no word at all
    fi
    if [ "$ok" = 1 ]; then newkeep="$newkeep $k"; else DENY_IDX="$DENY_IDX $k"; WG_IDX="$WG_IDX $k"; DENIED=$((DENIED+1)); fi
  done
  shopt -u nocasematch
  KEEP="$newkeep"
}

# ---- hit descriptions --------------------------------------------------------------------------
# DESC is the public one-line description of a kit-public hit, read from the kit root (never the
# cwd) and only for a hit that already passed the allowlist. Builtins only: no process spawn per hit.
DESC=""

# first_comment <file>: DESC = the first descriptive comment line (shebang, shellcheck and
# kit-verb lines skipped; a leading "name.sh -- " label dropped), continued over the following
# comment lines up to the first bare '#' line or 160 characters. 20 lines at most.
first_comment() {
  local f="$1" line n=0
  DESC=""
  [ -f "$f" ] || return 0
  while [ "$n" -lt 20 ] && IFS= read -r line; do
    n=$((n+1))
    case "$line" in
      '#!'*|'# shellcheck'*|'# kit-verb:'*) continue ;;
      ''|'#'*) line="${line#\#}"; line="${line#"${line%%[![:space:]]*}"}"
            if [ -z "$line" ]; then [ -z "$DESC" ] && continue; return 0; fi
            if [ -z "$DESC" ]; then
              case "${line%% -- *}" in *[[:space:]]*|"$line") ;; *) line="${line#* -- }" ;; esac
              DESC="$line"
            else DESC="$DESC $line"; fi
            [ "${#DESC}" -lt 160 ] || return 0 ;;
      *) return 0 ;;
    esac
  done < "$f"
}

# fm_description <file>: DESC = the one-line `description:` of the YAML frontmatter, quotes dropped.
fm_description() {
  local f="$1" line n=0 v
  DESC=""
  [ -f "$f" ] || return 0
  while [ "$n" -lt 30 ] && IFS= read -r line; do
    n=$((n+1)); line="${line%$'\r'}"
    if [ "$n" = 1 ]; then [ "$line" = '---' ] || return 0; continue; fi
    [ "$line" != '---' ] || return 0
    case "$line" in
      description:*)
        v="${line#description:}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
        case "$v" in ''|'>'*|'|'*) return 0 ;; esac
        case "$v" in \"*\") v="${v#\"}"; v="${v%\"}" ;; \'*\') v="${v#\'}"; v="${v%\'}" ;; esac
        DESC="$v"; return 0 ;;
    esac
  done < "$f"
}

# describe_hit <name>: DESC for a public name, else empty. bin/<name> first (its forwarded
# lib/<subsystem>/*.sh header wins over the forwarder's own banner), then commands, skills, agents.
describe_hit() {
  local h="$1" line fwd="" cut
  DESC=""
  if [ -f "$KIT_ROOT/bin/$h" ]; then
    while IFS= read -r line; do
      case "$line" in '#'*) continue ;; esac
      if [[ "$line" =~ (lib/[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+\.sh) ]]; then fwd="${BASH_REMATCH[1]}"; break; fi
    done < "$KIT_ROOT/bin/$h"
    [ -z "$fwd" ] || first_comment "$KIT_ROOT/$fwd"
    [ -n "$DESC" ] || first_comment "$KIT_ROOT/bin/$h"
  fi
  [ -n "$DESC" ] || fm_description "$KIT_ROOT/commands/$h.md"
  [ -n "$DESC" ] || fm_description "$KIT_ROOT/skills/$h/SKILL.md"
  [ -n "$DESC" ] || fm_description "$KIT_ROOT/agents/$h.md"
  DESC="${DESC//[[:cntrl:]]/}"
  if [ "${#DESC}" -gt 160 ]; then
    # Over the cap: end at the last whole sentence that fits, else the last word, else hard cut.
    DESC="${DESC:0:160}"
    case "$DESC" in
      *'. '*) DESC="${DESC%. *}." ;;
      *) cut="${DESC% *}"; [ "${#cut}" -lt 100 ] || DESC="$cut" ;;
    esac
  fi
  DESC="${DESC%:}"   # a byte bound only; the jq program caps at 160 characters
}

# BODY_PROG: the provider request body for the questions the guard kept. The question text is
# REBUILT from the template, the matched slots and the hit's own public description (kit files,
# never caller text); nothing the caller typed is forwarded.
BODY_PROG='
  ($idx | split(" ") | map(select(. != "") | tonumber)) as $keep
  | ($descs | split("\u001f")) as $dd
  | [ .questions | to_entries[] | select(.key as $k | any($keep[]; . == $k)) | .value ] as $kept
  | { model: $model, state: $state,
      questions: ( [ range(0; ($kept | length)) as $i
                     | { key: ("q" + (($i + 1) | tostring)),
                         value: { type: "choice", criteria: $criteria,
                                  instructions: ("Does the existing tool " + $kept[$i].hit
                                                       + (if ($dd[$i] // "") != "" then " (described as: " + ($dd[$i][0:160]) + ")" else "" end)
                                                       + " cover the job of the candidate " + $kept[$i].candidate + "?") } } ]
                   | from_entries ) }'

# ---- bounded command output --------------------------------------------------------------------
# TOK_DIR and TOK_PGID back tok_cleanup, so the EXIT trap kills a live group and removes the
# temp dir however flick leaves.
TOK_DIR=""; TOK_PGID=""

tok_cleanup() {
  [ -z "$TOK_PGID" ] || kill -s KILL -- "-$TOK_PGID" 2>/dev/null
  TOK_PGID=""
  [ -z "$TOK_DIR" ] || rm -rf "$TOK_DIR" 2>/dev/null
  TOK_DIR=""
}

# bounded_out <var> <argv...>: run argv WITHOUT a shell (no glob, no expansion, no quoting: the
# caller splits the words) under one hard limit. stdin is /dev/null, stderr is dropped, and
# stdout goes to a file in a 0700 temp dir that is removed before this returns; the output is
# never printed or logged. The file is capped by `ulimit -f` and the read by head -c. The
# command runs in its own process group (set -m), and the hard limit is background + poll +
# TERM to the group, then KILL after a short grace; flick never blocks on a command that
# ignores TERM. Bash 3.2 has no `wait -n`, no `timeout`.
# ponytail: a descendant that calls setsid/setpgid leaves the group and survives the kill.
# On a clean exit with at most 4096 bytes of stdout, <var> gets it minus one trailing newline
# and the return is 0; anything else leaves <var> empty and returns nonzero.
bounded_out() {
  local rv="$1"; shift
  local limit=10 cpid deadline raw rc=1
  [ "$CFG_TIMEOUT_MS" -le 10000 ] || limit=$((CFG_TIMEOUT_MS / 1000))
  TOK_DIR="$(umask 077; mktemp -d "${TMPDIR:-/tmp}/flick.XXXXXX" 2>/dev/null)" || { TOK_DIR=""; printf -v "$rv" '%s' ""; return 1; }
  [ -d "$TOK_DIR" ] || { TOK_DIR=""; printf -v "$rv" '%s' ""; return 1; }
  set -m
  ( ulimit -S -f 64 2>/dev/null; umask 077; exec "$@" ) </dev/null >"$TOK_DIR/out" 2>/dev/null &
  cpid=$!
  set +m
  TOK_PGID="$cpid"
  deadline=$((SECONDS + limit + 1))   # wall clock, not a loop count: a sleep spawn is slow on a hardened host
  while kill -0 "$cpid" 2>/dev/null; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      kill -s TERM -- "-$cpid" 2>/dev/null; kill -s TERM "$cpid" 2>/dev/null
      deadline=$((SECONDS + 1))
      while kill -0 "$cpid" 2>/dev/null && [ "$SECONDS" -lt "$deadline" ]; do sleep 0.1; done
      break
    fi
    sleep 0.1
  done
  if kill -0 "$cpid" 2>/dev/null; then
    kill -s KILL -- "-$cpid" 2>/dev/null; kill -s KILL "$cpid" 2>/dev/null
    tok_cleanup; printf -v "$rv" '%s' ""; return 1   # timed out: no wait, no output read
  fi
  wait "$cpid"; rc=$?
  # Stragglers the command left behind die with its group before the file is read.
  kill -s KILL -- "-$cpid" 2>/dev/null; TOK_PGID=""
  printf -v "$rv" '%s' ""
  if [ "$rc" = 0 ]; then
    raw="$(head -c 4097 "$TOK_DIR/out" 2>/dev/null; printf x)"
    raw="${raw%x}"
    if [ "${#raw}" -le 4096 ]; then printf -v "$rv" '%s' "${raw%$'\n'}"; else rc=1; fi
  fi
  tok_cleanup
  return "$rc"
}

# ---- token source ------------------------------------------------------------------------------
# resolve_token <env-name> <cmd>: sets TOKEN. The env var wins; only an empty one falls through
# to the configured command, for hosts that keep secrets out of the shell env. The command is
# split on whitespace and run WITHOUT a shell: no glob (set -f), no expansion, no quoting, and
# its first word must be an absolute path (a bare name would search the caller's PATH). The run
# itself, and its hard limit, is bounded_out's above.
resolve_token() {
  local envname="$1" cmd="$2" words
  TOKEN="${!envname:-}"
  [ -z "$TOKEN" ] || return 0
  [ -n "$cmd" ] || return 0
  set -f; read -ra words <<<"$cmd"; set +f
  [ "${#words[@]}" -gt 0 ] || return 0
  [ "${words[0]:0:1}" = / ] || return 0
  bounded_out TOKEN "${words[@]}" || true
}

# ---- transport ---------------------------------------------------------------------------------
JEV_URL='https://api.typesafe.ai/v1/systemone'
# Clef is Cloudflare Workers AI: same body Jev gets, answers arrive wrapped in the Cloudflare
# envelope ({"success":true,"errors":[],"result":<the Jev-shape object>}).
CLEF_API='https://api.cloudflare.com/client/v4/accounts'
RESP=""; CALL_ERR=""

# run_curl <url> <proto> <secs> <body> <token> <with-http2>: one request. Sets OUT and CURL_RC.
# -q must be curl's FIRST argument: only there does it mean "skip ~/.curlrc". The token, the
# body and the URL ride a curl config on stdin (printf is a builtin, so ps never shows any of
# them; the Clef URL carries the billing-tied account id), nothing touches disk, and there is
# no -L, so a redirect cannot carry the header elsewhere.
run_curl() {
  local url="$1" proto="$2" secs="$3" body="$4" token="$5" h2="$6" esc uesc
  local args=(-q --config - --silent --max-time "$secs" --proto "$proto" -w '\n%{http_code} %{time_total}')
  [ "$h2" = 1 ] && args[${#args[@]}]=--http2
  if [ "$proto" = '=http' ]; then args[${#args[@]}]=--noproxy; args[${#args[@]}]='*'; fi
  esc="${body//\\/\\\\}"; esc="${esc//\"/\\\"}"
  uesc="${url//\\/\\\\}"; uesc="${uesc//\"/\\\"}"
  OUT="$(printf 'header = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\ndata-raw = "%s"\nurl = "%s"\n' "$token" "$esc" "$uesc" | curl "${args[@]}")"
  CURL_RC=$?
}

# call_jev <body> <token>: sets RESP, LATENCY_MS and CALL_ERR (empty on a 2xx answer).
call_jev() {
  local body="$1" token="$2" url proto secs tail code tt ip fp ms h2=0
  if [ -n "$FLICK_URL_OK" ]; then url="$FLICK_URL_OK"; proto='=http'; else url="$JEV_URL"; proto='=https'; h2=1; fi
  ms=$((10#$CFG_TIMEOUT_MS))  # base 10: a zero-padded value must not read as octal
  secs="$(printf '%d.%03d' $((ms / 1000)) $((ms % 1000)))"
  run_curl "$url" "$proto" "$secs" "$body" "$token" "$h2"
  # A curl built without HTTP/2 refuses the flag (exit 4): retry once without it.
  if [ "$CURL_RC" = 4 ] && [ "$h2" = 1 ]; then run_curl "$url" "$proto" "$secs" "$body" "$token" 0; fi
  tail="${OUT##*$'\n'}"; RESP="${OUT%$'\n'*}"
  code="${tail%% *}"; tt="${tail#* }"
  if [[ "$tt" =~ ^[0-9]+(\.[0-9]*)?$ ]]; then
    ip="${tt%%.*}"; fp="000"; case "$tt" in *.*) fp="${tt#*.}000" ;; esac
    LATENCY_MS=$((10#$ip * 1000 + 10#${fp:0:3}))
  fi
  if [ "$CURL_RC" = 28 ]; then CALL_ERR=timeout
  elif [ "$CURL_RC" != 0 ]; then CALL_ERR=network
  elif ! [[ "$code" =~ ^[0-9]{3}$ ]] || [ "$code" = 000 ]; then CALL_ERR=network
  elif [ "${code:0:1}" != 2 ]; then CALL_ERR="http_$code"
  else CALL_ERR=""; fi
}

# call_clef <body> <token> <account>: same transport rules as call_jev (the FLICK_URL_OK test
# seam, one curl, the HTTP/2 retry), with the account id and model in the URL path. On a 2xx the
# Cloudflare envelope is unwrapped only when `success` is true and `.result` is an object, so
# the answer validation below sees the same shape Jev returns; a `success:false` envelope or a
# non-envelope body unwraps to an empty object, which the validator reports as malformed. The
# account id and the ref it came from are never logged or printed.
call_clef() {
  local body="$1" token="$2" account="$3" url proto secs tail code tt ip fp ms h2=0
  if [ -n "$FLICK_URL_OK" ]; then url="$FLICK_URL_OK"; proto='=http'; else url="$CLEF_API/$account/ai/run/@cf/cloudflare/$MODEL"; proto='=https'; h2=1; fi
  ms=$((10#$CFG_TIMEOUT_MS))
  secs="$(printf '%d.%03d' $((ms / 1000)) $((ms % 1000)))"
  run_curl "$url" "$proto" "$secs" "$body" "$token" "$h2"
  if [ "$CURL_RC" = 4 ] && [ "$h2" = 1 ]; then run_curl "$url" "$proto" "$secs" "$body" "$token" 0; fi
  tail="${OUT##*$'\n'}"; RESP="${OUT%$'\n'*}"
  code="${tail%% *}"; tt="${tail#* }"
  if [[ "$tt" =~ ^[0-9]+(\.[0-9]*)?$ ]]; then
    ip="${tt%%.*}"; fp="000"; case "$tt" in *.*) fp="${tt#*.}000" ;; esac
    LATENCY_MS=$((10#$ip * 1000 + 10#${fp:0:3}))
  fi
  if [ "$CURL_RC" = 28 ]; then CALL_ERR=timeout
  elif [ "$CURL_RC" != 0 ]; then CALL_ERR=network
  elif ! [[ "$code" =~ ^[0-9]{3}$ ]] || [ "$code" = 000 ]; then CALL_ERR=network
  elif [ "${code:0:1}" != 2 ]; then CALL_ERR="http_$code"
  else
    CALL_ERR=""
    RESP="$(printf '%s' "$RESP" | jq -c 'if .success == true and (.result|type) == "object" then .result else {} end' 2>/dev/null)"
  fi
}

# ---- decision log --------------------------------------------------------------------------------
# One JSON line per question in <log dir>/decide.jsonl. A sent question logs its slugs, so an
# operator can audit exactly what left the host; a denied one logs its index and reason only.
# The caller's id, any denied text, and the token never reach the log. `existing` is kept only
# when it is one of the point's choices. A failure to log never changes the answer.
LOG_BODY='(
  ["enhance","new","none"] as $choices
  | ($keep | split(" ") | map(select(. != "") | tonumber)) as $kidx
  | ($deny | split(" ") | map(select(. != "") | tonumber)) as $didx
  | ($wgidx | split(" ") | map(select(. != "") | tonumber)) as $wgi
  | $norm.questions as $all
  | [ ( $kidx[] as $i | $all[$i] as $q
      | ($out.answers[$q.id] // {}) as $a
      | {ts: (now | todate), backend: $backend, model: $model, point: $point, index: $i,
         latency_ms: $lat, candidate: $q.candidate, hit: $q.hit,
         chosen: ($a.choice // ""), existing: (if ($q.existing // "") as $e | $choices | index($e) then $q.existing else "" end),
         margin: ($a.margin // null), error: ($out.error), mode: $mode, mode_downgraded: $note} ),
    ( $didx[] as $i
      | {ts: (now | todate), backend: $backend, model: $model, point: $point, index: $i,
         latency_ms: $lat, chosen: "", error: "egress_denied",
         reason: (if ($wgi | index($i)) != null then $wgreason else $dreason end), mode: $mode, mode_downgraded: $note} ) ]
  | sort_by(.index) | .[] | tojson )'

# log_target: print the decide.jsonl path, or nothing when the log dir cannot be resolved.
# Same precedence as kit_resolve_log_dir, but the [ledger] location read is root-only: the log
# holds the slugs that left the host, so a project .kit.toml must not be able to move it.
log_target() {
  local dir loc
  if [ "${KIT_LEDGER_DIR+set}" = set ]; then dir="$KIT_LEDGER_DIR"
  elif [ -n "${DWARVES_KIT_LOG_DIR:-}" ]; then dir="$DWARVES_KIT_LOG_DIR"
  else
    loc="$(kit_config_get_root ledger.location shared 2>/dev/null)"
    case "$loc" in
      isolated) dir="$PWD/.kit/logs" ;;
      shared|"") dir="${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs" ;;
      *) dir="$loc" ;;
    esac
  fi
  [ -n "$dir" ] || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s/decide.jsonl' "$dir"
}

# ---- validation and output -----------------------------------------------------------------------
# FINAL_PROG builds the envelope. An answer set counts only when the provider answered exactly
# the requested ids, each with exactly the offered choices, probabilities summing to about 1,
# and a stated choice equal to the unique argmax. Anything else is bad_probs; a body that is
# not a JSON object holding answers is malformed. One bad answer voids the whole call.
FINAL_PROG='
  def abs: if . < 0 then -. else . end;
  def judged($cs):
    if type == "object" and ((.probabilities | type) == "object")
       and ((.probabilities | keys) == $cs)
       and (.probabilities | all(.[]; type == "number" and . >= 0 and . <= 1))
       and ((((.probabilities | add) - 1) | abs) <= 0.03)
    then (.probabilities | to_entries | sort_by(-.value)) as $s
         | if ($s[0].value > $s[1].value) and (.choice == $s[0].key)
           then {choice: .choice, probs: .probabilities, margin: ($s[0].value - $s[1].value)}
           else null end
    else null end;
  ($keep | split(" ") | map(select(. != "") | tonumber)) as $kidx
  | ($deny | split(" ") | map(select(. != "") | tonumber)) as $didx
  | $norm.questions as $all
  | [ $kidx[] | $all[.] ] as $kept
  | ($criteria | keys) as $cs
  | [ range(0; ($kept | length)) | "q\(. + 1)" ] as $qids
  | (try ($resp | fromjson) catch null) as $r
  | ( if $err != "" then {err: $err}
      elif (($r | type) != "object") or (($r.answers | type) != "object") then {err: "malformed"}
      elif (($r.answers | keys) != ($qids | sort)) then {err: "bad_probs"}
      else ( [ range(0; ($kept | length)) as $i | ($r.answers[$qids[$i]] | judged($cs)) ] ) as $j
           | if ($j | all(. != null)) then {ok: $j} else {err: "bad_probs"} end
      end ) as $res
  | ( if $res.ok then
      { backend: $backend, model: $model, latency_ms: $lat, mode: $mode,
        answers: ( [ range(0; ($kept | length)) as $i | {key: $kept[$i].id, value: $res.ok[$i]} ]
                   + [ $didx[] | {key: $all[.].id, value: {choice: "", error: "egress_denied"}} ] | from_entries ),
        error: "",
        counts: {answered: ($kept | length), denied: ($didx | length), error: 0} }
    else
      { backend: $backend, model: $model, latency_ms: $lat, mode: $mode, answers: {},
        error: $res.err,
        counts: {answered: 0, denied: ($didx | length), error: (($all | length) - ($didx | length))} }
    end ) as $out
  | ($out | tojson),
'

# finalize <error>: the post-guard exit. <error> is empty after a 2xx answer; the program decides
# whether that answer is acceptable.
finalize() {
  local all out target
  target="$(log_target)"
  all="$(jq -r --argjson norm "$NORM" --arg keep "${KEEP# }" --arg deny "${DENY_IDX# }" \
    --arg err "$1" --arg resp "${RESP:-}" --arg dreason "$DENY_REASON" --arg wgidx "${WG_IDX# }" --arg wgreason "$WG_REASON" --arg backend "$BACKEND" --arg model "$MODEL" \
    --argjson lat "${LATENCY_MS:-0}" --arg mode "$MODE_OUT" --arg point "wrap-7b" \
    --argjson note "${MODE_NOTE:-false}" --argjson criteria "$POINT_WRAP_7B_CRITERIA" \
    -n "$FINAL_PROG$LOG_BODY")" || exit 0
  out="${all%%$'\n'*}"
  [ -n "$out" ] || exit 0
  if [ -n "$target" ] && [ "$all" != "$out" ]; then ( umask 077; printf '%s\n' "${all#*$'\n'}" >> "$target" ) 2>/dev/null || true; fi
  printf '%s\n' "$out"; EMITTED=1; exit 0
}

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

  # A test-only URL override: honoured only with FLICK_TEST=1, and then only for a loopback http
  # URL with no userinfo. Without FLICK_TEST=1 the variable is ignored and production stays https.
  FLICK_URL_OK=""
  if [ "${FLICK_TEST:-}" = 1 ] && [ -n "${FLICK_URL:-}" ]; then
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
  [ "$BACKEND" = clef ] && MODEL="$CFG_CLEF_MODEL"
  MODE_NOTE=false; [ "$CFG_MODE" != decide ] || MODE_NOTE=true

  # No deny list, no egress: an operator who enables the point must also name what to block.
  local w dw_empty=1
  set -f; for w in $CFG_DENY_WORDS; do dw_empty=0; done; set +f
  if [ "$dw_empty" = 1 ]; then
    local j=0
    while [ "$j" -lt "$PARSED" ]; do DENY_IDX="$DENY_IDX $j"; j=$((j+1)); done
    DENIED="$PARSED"; DENY_REASON=deny_words_empty
    finalize egress_denied
  fi

  # Guard: drop every denied question BEFORE any body exists.
  build_public
  local i=0
  while [ "$i" -lt "$PARSED" ]; do
    if guard_ok "${Q_CAND[$i]}" "${Q_HIT[$i]}"; then KEEP="$KEEP $i"; else DENY_IDX="$DENY_IDX $i"; DENIED=$((DENIED+1)); fi
    i=$((i+1))
  done
  [ -n "$KEEP" ] || finalize egress_denied
  word_gate_apply
  [ -n "$KEEP" ] || finalize egress_denied

  # Descriptions only for kept (allowlisted) hits, in kept order, joined by the unit separator.
  local descs="" k
  for k in $KEEP; do describe_hit "${Q_HIT[$k]}"; descs="$descs$DESC$RS"; done

  local body
  body="$(printf '%s' "$NORM" | jq -c --arg idx "${KEEP# }" --arg model "$MODEL" --arg descs "$descs" \
    --arg state "$POINT_WRAP_7B_STATE" --argjson criteria "$POINT_WRAP_7B_CRITERIA" "$BODY_PROG")" || fail_all bad_input
  if [ "$verb" = body ]; then printf '%s\n' "$body"; EMITTED=1; exit 0; fi

  command -v curl >/dev/null 2>&1 || finalize missing_dep

  local tok_env="$CFG_JEV_TOKEN_ENV" tok_cmd="$CFG_JEV_TOKEN_CMD"
  if [ "$BACKEND" = clef ]; then tok_env="$CFG_CLEF_TOKEN_ENV"; tok_cmd="$CFG_CLEF_TOKEN_CMD"; fi
  [[ "$tok_env" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || finalize no_token
  TOKEN=""; resolve_token "$tok_env" "$tok_cmd"
  local token="$TOKEN"; TOKEN=""
  [ -n "$token" ] || finalize no_token
  case "$token" in *[[:cntrl:]\"\\]*) finalize no_token ;; esac

  if [ "$BACKEND" = clef ]; then
    # The account id is billing-tied: a literal value or an op:// ref resolved through
    # secret-cache-read (Keychain-cached), one cache name per ref like proof-asset's.
    # secret-cache-read comes from PATH, else the user's ~/.local/bin install, and the lookup
    # gets the same hard bound a token command gets (bounded_out). A missing or unresolvable
    # account is no_account, distinct from no_token: the token already resolved by this point.
    local acct="$CFG_CLEF_ACCOUNT" tag scr=""
    case "$acct" in
      op://*)
        scr="$(command -v secret-cache-read 2>/dev/null)"
        if [ -z "$scr" ] && [ -x "${HOME:-}/.local/bin/secret-cache-read" ]; then
          scr="${HOME}/.local/bin/secret-cache-read"
        fi
        [ -n "$scr" ] || finalize missing_dep
        tag="$(printf '%s' "$acct" | shasum -a 256 2>/dev/null | cut -c1-8)"
        bounded_out acct "$scr" --ttl 86400 "FLICK_CLEF_ACCT_$tag" "$acct" ;;
    esac
    [[ "$acct" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || finalize no_account
    call_clef "$body" "$token" "$acct"
  else
    call_jev "$body" "$token"
  fi
  finalize "$CALL_ERR"
}

main "$@"
