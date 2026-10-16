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
# Runs one case, prints one JSON line: {name, rc, stdout, stderr, log, stray} plus
# `files` when the case names a `read` list. Optional case fields:
#   seed  {"home/<path>": text, "cwd/<path>": text}  files written before the run (@HOME@ and @CWD@ expand;
#         a value starting "base64:" is decoded, for bytes a JSON string cannot hold, invalid UTF-8 included)
#   read  ["home/<path>", "cwd/<path>"]  files dumped after the run into `files`
#         (JSON-normalized when they parse, numbers canonical: 1000.0 reads 1000; null when missing)
#   touch {"home/<path>": <epoch>}  set a seeded file's mtime (a throttle stamp from the past)
#   args  ["--force"]  extra arguments appended to the hook command (@HOME@ and @CWD@ expand)
#   settle ["home/<glob>"]  after the hook returns, wait (up to 20 s) until nothing matches each
#         glob: a hook that hands its work to a detached child finishes after it exits
# A seeded file whose text starts with "#!" is made executable.
# Today's date folds to @TODAY@ in every output field, so a golden that carries a stamped date
# does not rot. The tokens @HOME@ and @CWD@ expand to the case's own temp directories in env values
# and payload text, and fold back in every output field, so goldens never carry a temp path.
hp_run_case() {
  local case_json="$1"; shift
  local T home cwd
  T="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
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
  local home_p cwd_p
  home_p=$(cd "$home" && pwd -P); cwd_p=$(cd "$cwd" && pwd -P)
  while IFS= read -r kv; do
    local k="${kv%%=*}" v="${kv#*=}"
    [ -n "${HP_ROOT:-}" ] && v="${v//ROOT/$HP_ROOT}"
    v="${v//@HOME@/$home}"; v="${v//@CWD@/$cwd}"; v="${v//@PATH@/$PATH}"
    envs+=("$k=$v")
  done < <(jq -r '(.env // {}) | to_entries[] | select(.value != null) | "\(.key)=\(.value)"' <<<"$case_json")

  local seed_key seed_path seed_text
  while IFS= read -r seed_key; do
    [ -n "$seed_key" ] || continue
    case "$seed_key" in
      home/*) seed_path="$home/${seed_key#home/}" ;;
      cwd/*)  seed_path="$cwd/${seed_key#cwd/}" ;;
      *) continue ;;
    esac
    mkdir -p "$(dirname "$seed_path")"
    seed_text=$(jq -j --arg k "$seed_key" '.seed[$k], "x"' <<<"$case_json"); seed_text=${seed_text%x}
    if [ "${seed_text#base64:}" != "$seed_text" ]; then
      printf '%s' "${seed_text#base64:}" | base64 -d > "$seed_path"   # raw bytes a JSON string cannot hold
    else
      seed_text="${seed_text//@HOME@/$home}"; seed_text="${seed_text//@CWD@/$cwd}"
      printf '%s' "$seed_text" > "$seed_path"
    fi
    [ "$(head -c 2 "$seed_path")" = "#!" ] && chmod +x "$seed_path"
  done < <(jq -r '(.seed // {}) | keys_unsorted[]' <<<"$case_json")
  local touch_key touch_epoch touch_path
  while IFS=$'\t' read -r touch_key touch_epoch; do
    [ -n "$touch_key" ] || continue
    case "$touch_key" in
      home/*) touch_path="$home/${touch_key#home/}" ;;
      cwd/*)  touch_path="$cwd/${touch_key#cwd/}" ;;
      *) continue ;;
    esac
    touch -t "$(date -r "$touch_epoch" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$touch_epoch" +%Y%m%d%H%M.%S)" "$touch_path"
  done < <(jq -r '(.touch // {}) | to_entries[] | "\(.key)\t\(.value)"' <<<"$case_json")
  local extra=() extra_arg
  while IFS= read -r extra_arg; do
    extra_arg="${extra_arg//@HOME@/$home}"; extra_arg="${extra_arg//@CWD@/$cwd}"
    extra+=("$extra_arg")
  done < <(jq -r '(.args // [])[]' <<<"$case_json")

  local payload="$T/payload" ptxt
  if [ "$(jq -r '.payload | type' <<<"$case_json")" = "object" ]; then
    ptxt=$(jq -c '.payload' <<<"$case_json")
    ptxt="${ptxt//@HOME@/$home}"; ptxt="${ptxt//@CWD@/$cwd}"
    printf '%s\n' "$ptxt" > "$payload"
  else
    local raw; raw=$(jq -j '.payload' <<<"$case_json")
    raw="${raw#RAW:}"; raw="${raw//@HOME@/$home}"; raw="${raw//@CWD@/$cwd}"
    printf '%s' "$raw" > "$payload"
  fi

  local eff=""
  if [ "$unset_log" != 1 ] && [ -n "$log_var" ]; then
    eff=$(printf '%s\n' ${envs[@]+"${envs[@]}"} | grep "^$log_var=" | tail -1 | cut -d= -f2-)
  fi

  local rc=0 out err
  err=$(cd "$cwd" && env -i PATH="$PATH" HOME="$home" TMPDIR="${TMPDIR:-/tmp}" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    ${envs[@]+"${envs[@]}"} "$@" ${extra[@]+"${extra[@]}"} < "$payload" 2>&1 >"$T/stdout") || rc=$?
  out=$(cat "$T/stdout")

  local settle_pat settle_glob settle_n
  while IFS= read -r settle_pat; do
    [ -n "$settle_pat" ] || continue
    case "$settle_pat" in
      home/*) settle_glob="$home/${settle_pat#home/}" ;;
      cwd/*)  settle_glob="$cwd/${settle_pat#cwd/}" ;;
      *) continue ;;
    esac
    settle_n=0
    while [ "$settle_n" -lt 100 ] && compgen -G "$settle_glob" >/dev/null; do sleep 0.2; settle_n=$((settle_n + 1)); done
  done < <(jq -r '(.settle // [])[]' <<<"$case_json")

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
        if [ "${f#home/}" != "$f" ]; then full="$home/${f#home/}"; else full="$cwd/${f#cwd/}"; fi
        [ "$full" = "$eff" ] || printf '%s\n' "$f"
      done | LC_ALL=C sort | paste -sd, -
  )

  local files="null" rp rpath rtxt
  if [ "$(jq -r 'has("read")' <<<"$case_json")" = "true" ]; then
    files="{}"
    while IFS= read -r rp; do
      case "$rp" in
        home/*) rpath="$home/${rp#home/}" ;;
        cwd/*)  rpath="$cwd/${rp#cwd/}" ;;
        *) continue ;;
      esac
      if [ -f "$rpath" ]; then
        rtxt=$(cat "$rpath")
        rtxt=$(jq -S -c 'walk(if type == "number" then . + 0 else . end)' <<<"$rtxt" 2>/dev/null) || rtxt=$(cat "$rpath")
        files=$(jq -c --arg k "$rp" --arg v "$rtxt" '.[$k] = $v' <<<"$files")
      else
        files=$(jq -c --arg k "$rp" '.[$k] = null' <<<"$files")
      fi
    done < <(jq -r '.read[]' <<<"$case_json")
  fi

  local today; today=$(date +%Y-%m-%d)
  norm=${norm//$today/@TODAY@}; err=${err//$today/@TODAY@}; logn=${logn//$today/@TODAY@}; files=${files//$today/@TODAY@}
  norm=${norm//$home_p/@HOME@}; norm=${norm//$home/@HOME@}; norm=${norm//$cwd_p/@CWD@}; norm=${norm//$cwd/@CWD@}
  err=${err//$home_p/@HOME@}; err=${err//$home/@HOME@}; err=${err//$cwd_p/@CWD@}; err=${err//$cwd/@CWD@}
  logn=${logn//$home_p/@HOME@}; logn=${logn//$home/@HOME@}; logn=${logn//$cwd_p/@CWD@}; logn=${logn//$cwd/@CWD@}
  files=${files//$home_p/@HOME@}; files=${files//$home/@HOME@}; files=${files//$cwd_p/@CWD@}; files=${files//$cwd/@CWD@}

  jq -c -n --arg name "$name" --argjson rc "$rc" --arg stdout "$norm" --arg stderr "$err" \
    --arg log "$logn" --arg stray "$stray" --argjson files "$files" \
    '{name:$name, rc:$rc, stdout:$stdout, stderr:$stderr, log:$log, stray:$stray}
     + (if $files == null then {} else {files:$files} end)'
}

# hp_gen_expected <rev> <hook-basename> <cases.jsonl> <expected.jsonl>
# Regenerates goldens from the Python hook at <rev>, run through that revision's own
# bash shim (so a Python crash reads the way the shim surfaced it).
# HP_EXTRA_FILES="lib/a.py lib/b.sh" copies more files from <rev>, at the same relative path, for a
# hook whose Python imports a sibling module (the hook sits in hooks/ beside lib/).
# HP_SILENT_CASES="name ..." marks cases where the Python crashed and the port
# deliberately exits 0 silently instead: their goldens become rc 0 with every
# output field empty (a spec-recorded divergence, never a way to hide a failure).
hp_gen_expected() {
  local rev="$1" hook="$2" cases_file="$3" expected_file="$4"
  local kit_root="${HP_KIT_ROOT:-}"
  [ -z "$kit_root" ] && kit_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local H; H="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; mkdir -p "$H/hooks" "$H/bin"
  git -C "$kit_root" show "${rev}:hooks/${hook}.sh" > "$H/hooks/$hook.sh"
  git -C "$kit_root" show "${rev}:hooks/${hook}.py" > "$H/hooks/$hook.py"
  local extra_file
  for extra_file in ${HP_EXTRA_FILES:-}; do
    mkdir -p "$H/$(dirname "$extra_file")"
    git -C "$kit_root" show "${rev}:${extra_file}" > "$H/$extra_file"
  done
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
