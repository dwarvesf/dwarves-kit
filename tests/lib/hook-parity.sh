#!/usr/bin/env bash
# hook-parity.sh -- sourced bash library shared by every Python-to-bash hook port's
# parity harness (money-gate, citation-guard, and the four queued next: backlog-stage,
# context-hints, harvest, intake-sweep). Bash 3.2 safe. Semantics lifted from the two
# hand-built harnesses (tests/fixtures/{money-gate,citation-guard}-parity/run-case.sh).
#
# A port's fixture usually collapses to:
#   source "$KIT_DIR/tests/lib/hook-parity.sh"
#   HP_LOG_VAR=MY_HOOK_LOG hp_run_case "$case_json" bash "$KIT_DIR/hooks/my-hook.sh"
#   hp_gen_expected ce08a00b my-hook fixtures/cases.jsonl fixtures/expected.jsonl
#   hp_check fixtures/cases.jsonl fixtures/expected.jsonl bash "$KIT_DIR/hooks/my-hook.sh"
# Hook-specific payload shaping (a generated large file, a path rewrite) stays in the
# port's own fixture; this library only knows the generic case shape.

# hp_run_case <case-json> <hook-cmd...>
# Runs one case, prints one JSON line: {name, rc, stdout, stderr, log, stray}.
hp_run_case() {
  local case_json="$1"; shift
  local T home cwd
  T="$(mktemp -d)"
  home="$T/home"; mkdir -p "$home"
  if [ -n "${HP_CWD:-}" ]; then cwd="$HP_CWD"; else cwd="$T/cwd"; mkdir -p "$cwd"; fi

  local name; name=$(jq -r '.name' <<<"$case_json")

  local log_var="${HP_LOG_VAR:-}" default_log="$T/harness.log"
  local envs=() unset_log=0
  if [ -n "$log_var" ]; then
    if [ "$(jq -r --arg k "$log_var" '(.env // {}) | has($k)' <<<"$case_json")" = "true" ]; then
      [ "$(jq -r --arg k "$log_var" '(.env // {})[$k] == null' <<<"$case_json")" = "true" ] && unset_log=1
    else
      envs+=("$log_var=$default_log")
    fi
  fi
  while IFS= read -r kv; do
    local k="${kv%%=*}" v="${kv#*=}"
    [ -n "${HP_ROOT:-}" ] && v="${v//ROOT/$HP_ROOT}"
    envs+=("$k=$v")
  done < <(jq -r '(.env // {}) | to_entries[] | select(.value != null) | "\(.key)=\(.value)"' <<<"$case_json")

  local payload="$T/payload"
  if [ "$(jq -r '.payload | type' <<<"$case_json")" = "object" ]; then
    jq -c '.payload' <<<"$case_json" > "$payload"
  else
    local raw; raw=$(jq -j '.payload' <<<"$case_json")
    printf '%s' "${raw#RAW:}" > "$payload"
  fi

  local eff=""
  if [ "$unset_log" != 1 ] && [ -n "$log_var" ]; then
    eff=$(printf '%s\n' ${envs[@]+"${envs[@]}"} | grep "^$log_var=" | tail -1 | cut -d= -f2-)
  fi

  local rc=0 out err
  err=$(cd "$cwd" && env -i PATH="$PATH" HOME="$home" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    ${envs[@]+"${envs[@]}"} "$@" < "$payload" 2>&1 >"$T/stdout") || rc=$?
  out=$(cat "$T/stdout")

  local norm; norm=$(jq -S -c . <<<"$out" 2>/dev/null) || norm="$out"

  local logn=""
  case "$eff" in
    /*) if [ -f "$eff" ]; then
          logn=$(cut -f2- "$eff")
          cut -f1 "$eff" | grep -qv '^[0-9][0-9]*$' && logn="BAD-EPOCH $logn"
        fi ;;
  esac

  local stray
  stray=$(
    { [ -d "$home" ] && (cd "$home" && find . -type f 2>/dev/null | sed 's|^\./|home/|')
      [ -d "$cwd" ] && (cd "$cwd" && find . -type f 2>/dev/null | sed 's|^\./|cwd/|')
    } | while IFS= read -r f; do
        case "$f" in
          home/*) full="$home/${f#home/}" ;;
          cwd/*)  full="$cwd/${f#cwd/}" ;;
        esac
        [ "$full" = "$eff" ] || printf '%s\n' "$f"
      done | LC_ALL=C sort | paste -sd, -
  )

  jq -c -n --arg name "$name" --argjson rc "$rc" --arg stdout "$norm" --arg stderr "$err" \
    --arg log "$logn" --arg stray "$stray" \
    '{name:$name, rc:$rc, stdout:$stdout, stderr:$stderr, log:$log, stray:$stray}'
}

# hp_gen_expected <rev> <hook-basename> <cases.jsonl> <expected.jsonl>
# Regenerates goldens from the Python hook at <rev>, run through that revision's own
# bash shim (so a Python crash reads the way the shim surfaced it).
# HP_SILENT_CASES="name ..." marks cases where the Python crashed and the port
# deliberately exits 0 silently instead: their goldens become rc 0 with every
# output field empty (a spec-recorded divergence, never a way to hide a failure).
hp_gen_expected() {
  local rev="$1" hook="$2" cases_file="$3" expected_file="$4"
  local kit_root="${HP_KIT_ROOT:-}"
  [ -z "$kit_root" ] && kit_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local H; H="$(mktemp -d)"; mkdir -p "$H/hooks" "$H/bin"
  git -C "$kit_root" show "${rev}:hooks/${hook}.sh" > "$H/hooks/$hook.sh"
  git -C "$kit_root" show "${rev}:hooks/${hook}.py" > "$H/hooks/$hook.py"
  # resolved once: under env -i a mise shim would reinstall python per call
  ln -s "$(python3 -c 'import sys; print(sys.executable)')" "$H/bin/python3"
  : > "$expected_file"
  while IFS= read -r c; do
    PATH="$H/bin:$PATH" hp_run_case "$c" bash "$H/hooks/$hook.sh" \
      | jq -c --arg silent " ${HP_SILENT_CASES:-} " \
          '.name as $n | if ($silent | contains(" " + $n + " ")) then .rc = 0 | .stdout = "" | .stderr = "" | .log = "" | .stray = "" else . end' \
      >> "$expected_file"
  done < "$cases_file"
}

# hp_check <cases.jsonl> <expected.jsonl> <hook-cmd...>
# Runs every case, prints FAIL <name> plus want/got for a mismatch, and a final
# "<N> passed, <M> failed" line. Returns non-zero on any failure.
hp_check() {
  local cases_file="$1" expected_file="$2"; shift 2
  local pass=0 fail=0
  while IFS= read -r c; do
    local name; name=$(jq -r '.name' <<<"$c")
    local exp got
    exp=$(grep -F "\"name\":\"$name\"" "$expected_file")
    got=$(hp_run_case "$c" "$@")
    if [ "$got" = "$exp" ]; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "  FAIL $name"
      echo "    want: $exp"
      echo "    got:  $got"
    fi
  done < "$cases_file"
  echo "$pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}
