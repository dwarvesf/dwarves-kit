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

echo
echo "flick: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
