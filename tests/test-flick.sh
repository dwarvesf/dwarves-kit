#!/usr/bin/env bash
# test-flick.sh -- flick, the fast decision CLI (lib/decide/flick.sh, bin/flick).
#
# Hermetic: a local stub (tests/lib/flick-stub.py, test-only) stands in for the provider and
# FLICK_URL points at it. Config comes from a temp operator kit.toml; the kit-root kit.toml and
# the real log dir are never read or written. The token is a canary string so a leak is greppable.
# Sections follow the spec's task order (SPEC-381): each one was red before its code existed.
#
# Skips cleanly (exit 0, one SKIP line) when curl, jq or python3 is missing.
#
# Run: bash tests/test-flick.sh   (also under /bin/bash 3.2: `/bin/bash tests/test-flick.sh`)
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FLICK="$KIT_DIR/bin/flick"
STUB="$KIT_DIR/tests/lib/flick-stub.py"

for dep in curl jq python3; do
  command -v "$dep" >/dev/null 2>&1 || { echo "SKIP: $dep not installed (flick needs curl and jq; the stub needs python3)"; exit 0; }
done

PASS=0; FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1${2:+ ($2)}" >&2; FAIL=$((FAIL+1)); }
# check <name> <exit-code-of-the-assertion>
check() { if [ "$2" = "0" ]; then ok "$1"; else bad "$1" "${3:-}"; fi; }
# jqt <name> <json> <jq-boolean-expression>
jqt() { if printf '%s' "$2" | jq -e "$3" >/dev/null 2>&1; then ok "$1"; else bad "$1" "json: $(printf '%s' "$2" | head -c 400)"; fi; }

T="$(mktemp -d)"
STUB_PID=""
cleanup() { { [ -n "$STUB_PID" ] && kill "$STUB_PID" && wait "$STUB_PID"; } 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

CANARY_TOKEN="CANARYTOKEN9f3a1c77"
mkdir -p "$T/op" "$T/root" "$T/home" "$T/log" "$T/cwd"

start_stub() {
  STUB_DIR="$T/stub"; mkdir -p "$STUB_DIR"
  python3 "$STUB" "$STUB_DIR" >/dev/null 2>&1 &
  STUB_PID=$!
  local i=0
  while [ ! -s "$STUB_DIR/port" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i+1)); done
  PORT="$(cat "$STUB_DIR/port" 2>/dev/null)"
}
stub_reset() { : > "$STUB_DIR/count"; : > "$STUB_DIR/bodies.log"; : > "$STUB_DIR/auth.log"; : > "$STUB_DIR/last.json"; }
stub_count() { local n; n="$(wc -l < "$STUB_DIR/count" 2>/dev/null | tr -d ' ')"; echo "${n:-0}"; }

# cfg <key=value>...: write the operator [decide] block (the only config layer flick reads here).
cfg() {
  { echo "[decide]"; local kv; for kv in "$@"; do echo "${kv%%=*} = \"${kv#*=}\""; done; } > "$T/op/kit.toml"
}

# flick_run <mode> <stdin-json> [extra env KEY=VAL...]: run bin/flick against the stub with a clean env.
flick_run() {
  local mode="$1" input="$2"; shift 2
  ( cd "$T/cwd" && printf '%s' "$input" | env -i PATH="$PATH" HOME="$T/home" \
      KIT_CONFIG_ROOT="$T/root" KIT_CONFIG_OPERATOR="$T/op" KIT_PROJECT_ROOT="$T/cwd" \
      DWARVES_KIT_LOG_DIR="$T/log" FLICK_URL="http://127.0.0.1:${PORT}/${mode}" \
      JEV_API_TOKEN="$CANARY_TOKEN" "$@" "$FLICK" "${FLICK_ARGS:-decide}" 2>/dev/null )
}

echo "== TASK-1: the stub itself behaves (tests are only as good as their stub) =="
start_stub
check "stub listens on a port" "$([ -n "${PORT:-}" ]; echo $?)"
stub_reset
body='{"model":"m","state":"s","questions":{"q1":{"type":"choice","criteria":{"a":"x","b":"y","c":"z"},"instructions":"i"},"q2":{"type":"choice","criteria":{"a":"x","b":"y"},"instructions":"i"}}}'
out="$(curl -s -X POST -H 'Authorization: Bearer t' --data-binary "$body" "http://127.0.0.1:${PORT}/ok")"
jqt "stub ok: one answer per requested id" "$out" '(.answers|keys) == ["q1","q2"]'
jqt "stub ok: probabilities sum to 1 and name the offered choices" "$out" '(.answers.q1.probabilities|keys) == ["a","b","c"] and (((.answers.q1.probabilities|add) - 1) | (if . < 0 then -. else . end)) < 0.001'
check "stub records one request" "$([ "$(stub_count)" = 1 ]; echo $?)"
check "stub records that a Bearer header arrived, not its value" "$([ "$(cat "$STUB_DIR/auth.log")" = bearer ]; echo $?)"
for m in 401 500; do
  code="$(curl -s -o /dev/null -w '%{http_code}' -X POST --data-binary "$body" "http://127.0.0.1:${PORT}/$m")"
  check "stub mode $m answers HTTP $m" "$([ "$code" = "$m" ]; echo $?)"
done
out="$(curl -s -X POST --data-binary "$body" "http://127.0.0.1:${PORT}/malformed")"
check "stub malformed is not JSON" "$(printf '%s' "$out" | jq -e . >/dev/null 2>&1; [ $? -ne 0 ]; echo $?)"
out="$(curl -s -X POST --data-binary "$body" "http://127.0.0.1:${PORT}/tie")"
jqt "stub tie: the top two probabilities are equal" "$out" '(.answers.q2.probabilities|[.a,.b]) == [0.5,0.5]'
out="$(curl -s -X POST --data-binary "$body" "http://127.0.0.1:${PORT}/missingkey")"
jqt "stub missingkey drops q1" "$out" '(.answers|keys) == ["q2"]'

IN1='{"point":"wrap-7b","questions":[{"id":"p1","candidate":"backlog-flip-script","hit":"board","existing":"enhance"}]}'
IN2='{"point":"wrap-7b","questions":[{"id":"p1","candidate":"backlog-flip-script","hit":"board"},{"id":"p2","candidate":"discord-thing","hit":"wrap"}]}'
EMPTYJSON='.answers == {} and (.counts|has("answered") and has("denied") and has("error"))'

# no_deps_path <jq|curl>: a PATH dir holding only what bin/flick itself needs (env, bash, dirname)
# plus the one dependency that is NOT hidden, so a missing-dependency run is real, not simulated.
no_deps_path() {
  local hide="$1" d="$T/path-no-$1" c
  [ -d "$d" ] && { printf '%s' "$d"; return; }
  mkdir -p "$d"
  for c in env bash dirname; do ln -sf "$(command -v "$c")" "$d/$c"; done
  [ "$hide" = jq ] || ln -sf "$(command -v jq)" "$d/jq"
  [ "$hide" = curl ] || ln -sf "$(command -v curl)" "$d/curl"
  printf '%s' "$d"
}

echo "== TASK-2: contract skeleton, closed error set, fail-open =="
check "bin/flick exists and is executable" "$([ -x "$FLICK" ]; echo $?)"
out="$("$FLICK" --help 2>&1)"; rc=$?
check "flick --help exits 0 and names the verbs" "$([ "$rc" = 0 ] && grep -q 'decide' <<<"$out" && grep -q 'body' <<<"$out"; echo $?)"
rm -f "$T/op/kit.toml"
stub_reset
out="$(flick_run ok "$IN1")"; rc=$?
jqt "default config: backend_none, empty answers, valid contract keys" "$out" "(.error == \"backend_none\") and $EMPTYJSON and has(\"backend\") and has(\"model\") and has(\"latency_ms\") and has(\"mode\")"
jqt "backend_none counts the one parsed question as error" "$out" '.counts == {"answered":0,"denied":0,"error":1}'
check "backend_none exits 0 and sends nothing" "$([ "$rc" = 0 ] && [ "$(stub_count)" = 0 ]; echo $?)"
cfg backend=jev points=""
out="$(flick_run ok "$IN2")"
jqt "point not enabled: point_disabled, both questions count as error" "$out" '.error == "point_disabled" and .counts == {"answered":0,"denied":0,"error":2}'
cfg backend=openai points=wrap-7b
stub_reset
out="$(flick_run ok "$IN1")"
jqt "backend openai: unsupported, counts error" "$out" '.error == "unsupported" and .counts.error == 1 and .answers == {}'
check "openai stub sends nothing" "$([ "$(stub_count)" = 0 ]; echo $?)"
cfg backend=jev points=wrap-7b
out="$(flick_run ok "not json at all")"
jqt "stdin that is not JSON: bad_input, all counts zero" "$out" '.error == "bad_input" and .counts == {"answered":0,"denied":0,"error":0}'
out="$(flick_run ok '{"point":"no-such-point","questions":[{"id":"a"}]}')"
jqt "unknown point: bad_input" "$out" '.error == "bad_input"'
out="$(flick_run ok "$IN1" JEV_API_TOKEN=)"
jqt "no token: no_token, counts error" "$out" '.error == "no_token" and .counts.error == 1'
cfg backend=jev points=wrap-7b jev_token_env='BAD NAME'
out="$(flick_run ok "$IN1")"
jqt "token env name with a space: no_token" "$out" '.error == "no_token"'
cfg backend=jev points=wrap-7b jev_token_env='X;touch /tmp/pwn'
out="$(flick_run ok "$IN1")"
jqt "token env name with shell syntax: no_token" "$out" '.error == "no_token"'
cfg backend=jev points=wrap-7b
for bad in 'abc"def' 'abc\def'; do
  out="$(flick_run ok "$IN1" "JEV_API_TOKEN=$bad")"
  jqt "token holding a quote or backslash is refused: no_token" "$out" '.error == "no_token"'
done
out="$(flick_run ok "$IN1" "JEV_API_TOKEN=$(printf 'abc\ndef')")"
jqt "token holding a newline is refused: no_token" "$out" '.error == "no_token"'
out="$(PATH="$(no_deps_path jq)" flick_run ok "$IN1")"
jqt "jq missing: missing_dep, valid JSON from the fixed fallback, counts zero" "$(printf '%s' "$out" | jq -c . 2>/dev/null)" '.error == "missing_dep" and .answers == {} and .counts == {"answered":0,"denied":0,"error":0}'
out="$(PATH="$(no_deps_path curl)" flick_run ok "$IN1")"
jqt "curl missing: missing_dep, the parsed question counts as error" "$out" '.error == "missing_dep" and .counts.error == 1'

echo "== TASK-2: garbage never breaks the contract (EXIT trap) =="
fuzz_ok=0; fuzz_n=0
fuzz() { # <label> <config-lines-or-empty> <stdin>
  fuzz_n=$((fuzz_n+1))
  local o rc
  o="$(flick_run ok "$3")"; rc=$?
  if [ "$rc" = 0 ] && printf '%s' "$o" | jq -e '.answers != null and (.error|type=="string") and (.counts|type=="object")' >/dev/null 2>&1; then fuzz_ok=$((fuzz_ok+1)); else bad "fuzz $1" "rc=$rc out=$(printf '%s' "$o" | head -c 200)"; fi
}
cfg backend=jev points=wrap-7b
fuzz "empty stdin" x ""
fuzz "json null" x "null"
fuzz "json array" x "[]"
fuzz "questions not an array" x '{"point":"wrap-7b","questions":"x"}'
fuzz "binary bytes" x "$(head -c 300 /dev/urandom | tr -d '\0')"
fuzz "deep nesting" x "$(printf '[%.0s' $(seq 1 300))"
fuzz "huge string" x "{\"point\":\"wrap-7b\",\"questions\":[{\"id\":\"$(head -c 70000 /dev/zero | tr '\0' a)\"}]}"
cfg backend='jev"; echo hi' points='$(touch '"$T"'/pwned) `id`' timeout_ms='abc' mode='x\\y' jev_model="$(printf 'a\nb')" allow_names='*' deny_words='['
fuzz "garbage config" x "$IN1"
check "garbage config executed nothing" "$([ ! -e "$T/pwned" ]; echo $?)"
cfg backend=jev points=wrap-7b timeout_ms=-5 mode=decide
fuzz "negative timeout, mode decide" x "$IN1"
check "every fuzz case exits 0 with a valid envelope ($fuzz_ok of $fuzz_n)" "$([ "$fuzz_ok" = "$fuzz_n" ]; echo $?)"
cfg backend=jev points=wrap-7b

# --- sections above; summary below ---
echo
echo "flick: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
