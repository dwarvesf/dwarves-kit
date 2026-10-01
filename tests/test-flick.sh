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
stub_reset() { : > "$STUB_DIR/count"; : > "$STUB_DIR/bodies.log"; : > "$STUB_DIR/auth.log"; : > "$STUB_DIR/authsha.log"; : > "$STUB_DIR/last.json"; }
stub_count() { local n; n="$(wc -l < "$STUB_DIR/count" 2>/dev/null | tr -d ' ')"; echo "${n:-0}"; }

# cfg <key=value>...: write the operator [decide] block (the only config layer flick reads here).
# deny_words defaults to a harmless word: flick refuses to send anything while the list is empty,
# so a test that wants an empty list passes deny_words= explicitly. word_gate defaults to off so the
# older sections (made-up slugs, host-independent) keep testing what they test; the word-gate section
# uses wg_cfg, which omits the key to get the shipped default (on).
cfg() {
  local kv hasdeny=0 haswg=0
  { echo "[decide]"; for kv in "$@"; do case "$kv" in deny_words=*) hasdeny=1 ;; word_gate=*) haswg=1 ;; esac; echo "${kv%%=*} = \"${kv#*=}\""; done
    [ "$hasdeny" = 1 ] || echo 'deny_words = "zzprivatecorp"'
    [ "$haswg" = 1 ] || echo 'word_gate = "off"'; } > "$T/op/kit.toml"
}

# flick_run <mode> <stdin-json> [extra env KEY=VAL...]: run bin/flick against the stub with a clean env.
flick_run() {
  local mode="$1" input="$2"; shift 2
  ( cd "${FLICK_CWD:-$T/cwd}" && printf '%s' "$input" | env -i PATH="$PATH" HOME="$T/home" \
      KIT_CONFIG_ROOT="$T/root" KIT_CONFIG_OPERATOR="$T/op" KIT_PROJECT_ROOT="$T/cwd" \
      DWARVES_KIT_LOG_DIR="$T/log" FLICK_TEST=1 FLICK_URL="http://127.0.0.1:${PORT}/${mode}" \
      JEV_API_TOKEN="$CANARY_TOKEN" "$@" "${FLICK_BIN:-$FLICK}" "${FLICK_ARGS:-decide}" 2>/dev/null )
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

# body_run <stdin-json> [env...]: run `flick body` (the guarded request body, no network).
body_run() { local in="$1"; shift; FLICK_ARGS=body flick_run ok "$in" "$@"; }
q() { # q <id> <candidate> <hit> : one question object
  jq -nc --arg id "$1" --arg c "$2" --arg h "$3" '{id:$id,candidate:$c,hit:$h}'
}
req() { # req <question-json>... : a wrap-7b request around those questions
  local joined; joined="$(printf '%s\n' "$@" | jq -sc .)"
  jq -nc --argjson qs "$joined" '{point:"wrap-7b",questions:$qs}'
}

echo "== TASK-3: input contract (slots, id remap, existing filter, extra fields) =="
cfg backend=jev points=wrap-7b
out="$(body_run "$IN1")"
jqt "body: one question becomes q1 with the point's template text" "$out" '(.questions|keys) == ["q1"] and (.questions.q1.instructions | test("^Does the existing tool board( \\(described as: [^)]+\\))? cover the job of the candidate backlog-flip-script[?]$")) and .model == "jev-1.13.0" and .questions.q1.type == "choice"'
jqt "body: criteria come from the registry, three choices" "$out" '(.questions.q1.criteria|keys) == ["enhance","new","none"] and (.questions.q1.criteria|map(type=="string" and length > 10)|all)'
jqt "body: a fixed state preamble, no caller text" "$out" '(.state|type=="string") and (.state|length) > 20'
out="$(body_run '{"point":"wrap-7b","questions":[{"id":"CANARYID99","candidate":"backlog-flip-script","hit":"board","existing":"CANARYEXIST77"}]}')"
check "caller id and existing never reach the request body" "$(grep -q 'CANARYID99\|CANARYEXIST77' <<<"$out"; [ $? -ne 0 ]; echo $?)"
jqt "body for that request is still a normal q1 body" "$out" '(.questions|keys) == ["q1"]'
out="$(body_run "$(req "$(q p1 backlog-flip-script board)" "$(q p2 discord-poster wrap)")")"
jqt "ids p1 p2 go to the provider as q1 q2" "$out" '(.questions|keys) == ["q1","q2"] and (.questions.q2.instructions|test("tool wrap( \\(.*\\))? cover"))'
for payload in \
  '{"point":"wrap-7b","questions":[{"id":"p1","candidate":"backlog-flip-script","hit":"board"}],"extra":1}' \
  '{"point":"wrap-7b","questions":[{"id":"p1","candidate":"backlog-flip-script","hit":"board","context":"hello"}]}' \
  '{"point":"wrap-7b","questions":[{"id":"p1","candidate":"backlog-flip-script","hit":"board","question":"free text"}]}' \
  '{"point":"wrap-7b","questions":[{"id":"p1","candidate":"backlog-flip-script"}]}' \
  '{"point":"wrap-7b","questions":[]}' \
  '{"point":"wrap-7b","questions":[{"id":"p 1","candidate":"backlog-flip-script","hit":"board"}]}' \
  '{"point":"wrap-7b","questions":[{"id":"p1","candidate":"backlog-flip-script","hit":"board","existing":5}]}' \
  '{"point":"wrap-7b","questions":[{"id":"p1","candidate":"a\nb-script","hit":"board"}]}' \
  '{"point":"wrap-7b","questions":[{"id":"p1","candidate":"backlog-flip-script","hit":"board\u0001"}]}' \
  '{"point":"wrap-7b","questions":[{"id":"p1","candidate":"backlog-flip-script","hit":"board","existing":"en\thance"}]}' \
  '{"point":"wrap-7b","questions":[{"id":"p1","candidate":"backlog-flip-script","hit":"board"},{"id":"p1","candidate":"discord-poster","hit":"wrap"}]}' ; do
  out="$(body_run "$payload")"
  jqt "bad input is refused whole: $(printf '%s' "$payload" | head -c 60)" "$out" '.error == "bad_input" and .counts == {"answered":0,"denied":0,"error":0}'
done
over="$(jq -nc '{point:"wrap-7b",questions:[range(0;51)|{id:"p\(.)",candidate:"backlog-flip-script",hit:"board"}]}')"
out="$(body_run "$over")"
jqt "more than 50 questions is bad_input" "$out" '.error == "bad_input"'
out="$(body_run "$IN1
")"
jqt "a trailing newline after the JSON document is fine" "$out" '(.questions|keys) == ["q1"]'

echo "== TASK-4: egress guard (kit root, exact match, deny_words, mixed batch) =="
mkdir -p "$T/foreign/bin" "$T/foreign/commands"
: > "$T/foreign/bin/acme-client-tool"; chmod +x "$T/foreign/bin/acme-client-tool"
: > "$T/foreign/commands/client-secret-cmd.md"
out="$(FLICK_CWD="$T/foreign" body_run "$(req "$(q p1 backlog-flip-script acme-client-tool)")")"
jqt "a foreign cwd bin/ holding a client-style name does not widen the allowlist" "$out" '.error == "egress_denied" and .counts == {"answered":0,"denied":1,"error":0}'
out="$(FLICK_CWD="$T/foreign" body_run "$(req "$(q p1 backlog-flip-script client-secret-cmd)")")"
jqt "a foreign cwd commands/ name is denied too" "$out" '.error == "egress_denied"'
out="$(FLICK_CWD="$T/foreign" body_run "$(req "$(q p1 backlog-flip-script board)")")"
jqt "a public name from the kit root still passes from a foreign cwd" "$out" '(.questions|keys) == ["q1"]'
for hit in boardx xboard boar Board BOARD "board " " board" "board-" "bo ard" 'bo*' 'b?ard' 'board;ls' '../bin/board' board.md bin/board; do
  out="$(body_run "$(req "$(q p1 backlog-flip-script "$hit")")")"
  jqt "hit '$hit' is not an exact public name: egress_denied, no body" "$out" '.error == "egress_denied" and .answers == {}'
done
out="$(body_run "$(req "$(jq -nc '{id:"p1",candidate:"backlog-flip-script",hit:"board\n"}')")")"
jqt "a hit with a trailing newline is refused (bad_input), never matched as 'board'" "$out" '.error == "bad_input"'
for sk in skills agents; do :; done
pub_skill="$(ls "$KIT_DIR/skills" | head -1)"; pub_agent="$(ls "$KIT_DIR/agents" | head -1)"; pub_agent="${pub_agent%.md}"
out="$(body_run "$(req "$(q p1 backlog-flip-script "$pub_skill")" "$(q p2 backlog-flip-script "$pub_agent")")")"
jqt "skills/ dirs and agents/ files count as public names" "$out" '(.questions|keys) == ["q1","q2"]'
for cand in Backlog-Flip ab 'has space' "$(printf 'a%.0s' $(seq 1 41))" 'under_score' 'dot.name'; do
  out="$(body_run "$(req "$(q p1 "$cand" board)")")"
  jqt "candidate '$cand' fails the slug rule: egress_denied" "$out" '.error == "egress_denied"'
done
cfg backend=jev points=wrap-7b deny_words="Acme foo"
for cand in acme-sync sync-acme-x fooz xfoo-bar; do
  out="$(body_run "$(req "$(q p1 "$cand" board)")")"
  jqt "deny_words (case-folded substring) blocks candidate $cand" "$out" '.error == "egress_denied" and .answers == {}'
  check "the denied candidate $cand is absent from the output" "$(grep -q "$cand" <<<"$out"; [ $? -ne 0 ]; echo $?)"
done
out="$(body_run "$(req "$(q p1 backlog-flip-script board)")")"
jqt "a candidate with no deny word still passes" "$out" '(.questions|keys) == ["q1"]'
cfg backend=jev points=wrap-7b allow_names="extra-public"
out="$(body_run "$(req "$(q p1 backlog-flip-script extra-public)" "$(q p2 backlog-flip-script extra-publ)")")"
jqt "allow_names adds an exact name only" "$out" '(.questions|keys) == ["q1"] and (.questions.q1.instructions|test("extra-public cover"))'
cfg backend=jev points=wrap-7b deny_words="acme"
mixed="$(req "$(q p1 backlog-flip-script board)" "$(q p2 acme-secret-plan board)" "$(q p3 build-thing secret-client-tool)" "$(q p4 discord-poster wrap)")"
out="$(body_run "$mixed")"
jqt "mixed batch: the body holds only the allowed questions, renumbered q1 q2" "$out" '(.questions|keys) == ["q1","q2"] and (.questions.q1.instructions|test("board( \\(.*\\))? cover")) and (.questions.q2.instructions|test("tool wrap( \\(.*\\))? cover"))'
check "mixed batch: no denied text in the body" "$(grep -q 'acme-secret-plan\|secret-client-tool\|build-thing' <<<"$out"; [ $? -ne 0 ]; echo $?)"
stub_reset
out="$(body_run "$IN1" "JEV_API_TOKEN=$CANARY_TOKEN")"
check "flick body prints no token" "$(grep -q "$CANARY_TOKEN" <<<"$out"; [ $? -ne 0 ]; echo $?)"
check "flick body makes zero stub requests" "$([ "$(stub_count)" = 0 ]; echo $?)"
cfg backend=jev points=wrap-7b

# decide_run <mode> <stdin-json> [env...]: run `flick decide` against the stub.
decide_run() { local m="$1" in="$2"; shift 2; FLICK_ARGS=decide flick_run "$m" "$in" "$@"; }
ms_now() { python3 -c 'import time;print(int(time.monotonic()*1000))'; }
IN3="$(req "$(q p1 backlog-flip-script board)" "$(q p2 discord-poster wrap)" "$(q p3 sync-helper precedent)")"

echo "== TASK-5: Jev transport (one request per batch, curl hygiene, timeouts, HTTP errors) =="
cfg backend=jev points=wrap-7b
stub_reset
out="$(decide_run ok "$IN3")"
check "a 3-question batch is ONE request" "$([ "$(stub_count)" = 1 ]; echo $?)"
jqt "the stub received q1 q2 q3 only, rebuilt from the template" "$(cat "$STUB_DIR/last.json")" '(.questions|keys) == ["q1","q2","q3"] and (.questions.q1.instructions | test("^Does the existing tool board( \\(.*\\))? cover the job of the candidate backlog-flip-script[?]$"))'
check "the Bearer header reached the stub" "$([ "$(cat "$STUB_DIR/auth.log")" = bearer ]; echo $?)"
check "the token is nowhere in the request body or stdout" "$(grep -q "$CANARY_TOKEN" "$STUB_DIR/bodies.log" <<<"$out"; [ $? -ne 0 ] && ! grep -q "$CANARY_TOKEN" "$STUB_DIR/bodies.log"; echo $?)"
jqt "envelope: backend jev, pinned model, mode shadow, integer latency" "$out" '.backend == "jev" and .model == "jev-1.13.0" and .mode == "shadow" and (.latency_ms|type=="number") and .latency_ms >= 0'
stub_reset
t0="$(ms_now)"; out="$(decide_run slow "$IN3")"; t1="$(ms_now)"
jqt "slow stub: timeout, all three counted as error" "$out" '.error == "timeout" and .answers == {} and .counts == {"answered":0,"denied":0,"error":3}'
check "the 1500 ms floor held: the call waited at least 1.4 s and gave up before the stub's 4 s" "$([ $((t1-t0)) -ge 1400 ] && [ $((t1-t0)) -lt 3800 ]; echo $?)" "took $((t1-t0)) ms"
for code in 401 500; do
  out="$(decide_run "$code" "$IN3")"
  jqt "HTTP $code: http_$code, empty answers, all error" "$out" ".error == \"http_$code\" and .answers == {} and .counts == {\"answered\":0,\"denied\":0,\"error\":3}"
done
out="$(PORT=1 decide_run ok "$IN3")"
jqt "connection refused: network" "$out" '.error == "network" and .counts.error == 3'
stub_reset
for url in 'http://127.0.0.1@evil.example/' 'http://localhost.evil.example/' 'http://127.0.0.1.evil.example/' 'http://user:pw@127.0.0.1/' 'https://127.0.0.1/' 'http://127.0.0.1:80@evil.example/' 'http://localhost:8080evil/' 'ftp://127.0.0.1/' 'http://127.0.0.1/ok x' 'http://127.0.0.1/ok
http://evil.example/'; do
  out="$(decide_run ok "$IN3" "FLICK_URL=$url")"
  jqt "FLICK_URL $(printf '%s' "$url" | tr '\n' ' ') is refused: bad_input" "$out" '.error == "bad_input" and .counts == {"answered":0,"denied":0,"error":0}'
done
check "no refused FLICK_URL produced a request" "$([ "$(stub_count)" = 0 ]; echo $?)"
echo "-- curl hygiene --"
mkdir -p "$T/curlhome"
printf 'trace = "%s/canary.trace"\n' "$T/curlhome" > "$T/curlhome/.curlrc"
env -u CURL_HOME -u XDG_CONFIG_HOME HOME="$T/curlhome" curl -s -o /dev/null -X POST --data x "http://127.0.0.1:${PORT}/ok"
check "the canary .curlrc really fires for a plain curl (so the test below is not vacuous)" "$([ -s "$T/curlhome/canary.trace" ]; echo $?)"
mv -f "$T/curlhome/canary.trace" "$T/canary.fired"
stub_reset
out="$(decide_run ok "$IN3" HOME="$T/curlhome")"
jqt "flick still answers with a hostile HOME" "$out" '.error == ""'
check "the canary .curlrc had no effect on flick (-q is curl's first argument)" "$([ ! -e "$T/curlhome/canary.trace" ]; echo $?)"
check "no Bearer header or token reached disk under that HOME" "$(grep -rq "Bearer\|$CANARY_TOKEN" "$T/curlhome"; [ $? -ne 0 ]; echo $?)"
check "source pin: -q is the first curl argument, production proto is =https, no -L" "$(grep -q 'local args=(-q ' "$KIT_DIR/lib/decide/flick.sh" && grep -q -- "JEV_URL='https://" "$KIT_DIR/lib/decide/flick.sh" && grep -q -- '--proto "\$proto"' "$KIT_DIR/lib/decide/flick.sh" && grep -q "proto='=https'" "$KIT_DIR/lib/decide/flick.sh" && ! grep -E 'args(\[|=\()' "$KIT_DIR/lib/decide/flick.sh" | grep -Eq -- '-L|--location'; echo $?)"

echo "== TASK-6: Jev response validation (exact key sets, sum, unique argmax, margin) =="
out="$(decide_run ok "$IN3")"
jqt "valid answers, keyed by the caller's ids, with choice, probs and margin" "$out" '.error == "" and (.answers|keys) == ["p1","p2","p3"] and .answers.p1.choice == "enhance" and (.answers.p1.probs|keys) == ["enhance","new","none"] and (((.answers.p1.margin) - 0.55) | (if . < 0 then -. else . end)) < 0.0001'
jqt "counts for a clean batch" "$out" '.counts == {"answered":3,"denied":0,"error":0}'
cfg backend=jev points=wrap-7b deny_words=acme
out="$(decide_run ok "$(req "$(q p1 backlog-flip-script board)" "$(q p2 acme-secret-plan board)")")"
jqt "a denied question is reported per id, the allowed one answered" "$out" '.answers.p1.choice == "enhance" and .answers.p2 == {"choice":"","error":"egress_denied"} and .counts == {"answered":1,"denied":1,"error":0} and .error == ""'
cfg backend=jev points=wrap-7b deny_words=acme
stub_reset
out="$(decide_run ok "$(req "$(q p1 acme-secret-plan board)")")"
jqt "all denied: egress_denied, counts denied only" "$out" '.error == "egress_denied" and .answers == {} and .counts == {"answered":0,"denied":1,"error":0}'
check "a denied candidate (deny_words) produced zero stub requests" "$([ "$(stub_count)" = 0 ]; echo $?)"
stub_reset
out="$(decide_run ok "$(req "$(q p1 backlog-flip-script board)" "$(q p2 secret-thing no-such-public-tool)")")"
jqt "a non-public hit is egress_denied in a mixed batch, body holds one question" "$out" '.counts == {"answered":1,"denied":1,"error":0}'
check "the stub body held only the allowed question and none of the denied text" "$(jq -e '(.questions|keys)==["q1"]' "$STUB_DIR/last.json" >/dev/null && ! grep -q 'secret-thing\|no-such-public-tool' "$STUB_DIR/last.json"; echo $?)"
cfg backend=jev points=wrap-7b deny_words=acme
for m in malformed:malformed noanswers:malformed badprobs:bad_probs tie:bad_probs extrakey:bad_probs missingkey:bad_probs extraprob:bad_probs wrongchoice:bad_probs; do
  mode="${m%%:*}"; want="${m##*:}"
  out="$(decide_run "$mode" "$(req "$(q p1 backlog-flip-script board)" "$(q p2 acme-secret-plan board)" "$(q p3 discord-poster wrap)")")"
  jqt "stub $mode: $want, no answers, denied stays denied, the rest count as error" "$out" ".error == \"$want\" and .answers == {} and .counts == {\"answered\":0,\"denied\":1,\"error\":2}"
done
cfg backend=jev points=wrap-7b
cfg backend=jev points=wrap-7b mode=decide
out="$(decide_run ok "$IN1")"
jqt "mode decide is downgraded to shadow for wrap-7b" "$out" '.mode == "shadow" and .answers.p1.choice == "enhance"'
cfg backend=jev points=wrap-7b jev_model=jev-9.9.9
stub_reset
out="$(decide_run ok "$IN1")"
jqt "the pinned model comes from config and rides in the envelope and the request" "$out" '.model == "jev-9.9.9"'
check "request carried the pinned model" "$(jq -e '.model == "jev-9.9.9"' "$STUB_DIR/last.json" >/dev/null; echo $?)"
cfg backend=jev points=wrap-7b

echo "== TASK-8: decision log (sent slugs only, no token, no caller id, no denied text) =="
LOG="$T/log/decide.jsonl"
rm -f "$LOG"
cfg backend=none points=wrap-7b
out="$(decide_run ok "$IN1")"
check "backend none writes no log" "$([ ! -e "$LOG" ]; echo $?)"
cfg backend=jev points=wrap-7b deny_words=acme
stub_reset
mixed="$(jq -nc '{point:"wrap-7b",questions:[{id:"CANARYID55",candidate:"backlog-flip-script",hit:"board",existing:"CANARYEXIST66"},{id:"p2",candidate:"acme-secret-plan",hit:"board"},{id:"p3",candidate:"discord-poster",hit:"wrap",existing:"new"}]}')"
out="$(decide_run ok "$mixed")"
check "one log line per question (3)" "$([ "$(wc -l < "$LOG" | tr -d ' ')" = 3 ]; echo $?)"
check "every log line is a JSON object" "$(jq -e . "$LOG" >/dev/null 2>&1; echo $?)"
jqt "sent question 0: slugs, chosen, margin, filtered existing, shadow" "$(sed -n 1p "$LOG")" '.backend == "jev" and .model == "jev-1.13.0" and .point == "wrap-7b" and .index == 0 and .candidate == "backlog-flip-script" and .hit == "board" and .chosen == "enhance" and (.margin|type=="number") and .existing == "" and .error == "" and .mode == "shadow" and (.ts|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")) and (.latency_ms|type=="number")'
jqt "denied question: index and reason only, no slugs" "$(sed -n 2p "$LOG")" '.index == 1 and .error == "egress_denied" and (has("candidate")|not) and (has("hit")|not) and .chosen == ""'
jqt "an existing that IS a choice is kept" "$(sed -n 3p "$LOG")" '.existing == "new" and .candidate == "discord-poster"'
check "no token, caller id, canary existing or denied text in the log" "$(grep -q "$CANARY_TOKEN\|CANARYID55\|CANARYEXIST66\|acme-secret-plan\|\"p2\"\|\"p3\"" "$LOG"; [ $? -ne 0 ]; echo $?)"
rm -f "$LOG"
out="$(decide_run 500 "$IN1")"
jqt "a failed call logs the error against the sent slug" "$(cat "$LOG")" '.error == "http_500" and .chosen == "" and .candidate == "backlog-flip-script"'
rm -f "$LOG"
out="$(decide_run ok "$IN1" KIT_LEDGER_DIR=)"
jqt "an unresolvable log dir never changes the answer" "$out" '.error == "" and .answers.p1.choice == "enhance"'
check "and nothing was written" "$([ ! -e "$LOG" ]; echo $?)"
cfg backend=jev points=wrap-7b mode=decide
rm -f "$LOG"
out="$(decide_run ok "$IN1")"
jqt "mode decide logs the downgrade" "$(cat "$LOG")" '.mode == "shadow" and .mode_downgraded == true'
cfg backend=jev points=wrap-7b
echo "-- the token is not in the process list during a slow call --"
( decide_run slow "$IN1" >/dev/null ) &
SLOWPID=$!
# Poll: on a slow host curl starts well after the background run does, and lives only the 1.5 s timeout.
ps_all=""; ps_n=0
while [ "$ps_n" -lt 40 ]; do
  ps_all="$ps_all
$(ps -A -o args= 2>/dev/null)"
  grep -q 'curl .*--config' <<<"$ps_all" && break
  sleep 0.1; ps_n=$((ps_n+1))
done
check "ps shows no token while curl is in flight" "$(grep -q "$CANARY_TOKEN" <<<"$ps_all"; [ $? -ne 0 ]; echo $?)"
check "ps shows curl really was in flight (the check is not vacuous)" "$(grep -q 'curl .*--config' <<<"$ps_all"; echo $?)"
wait "$SLOWPID"

echo "== TASK-9: [decide] is root-only (a project .kit.toml changes nothing) =="
rm -f "$T/op/kit.toml"
printf '[decide]\nbackend = "jev"\npoints = "wrap-7b"\nallow_names = "evil-tool"\ndeny_words = ""\n' > "$T/cwd/.kit.toml"
stub_reset
out="$(decide_run ok "$IN1")"
jqt "a project .kit.toml cannot switch the backend on" "$out" '.error == "backend_none"'
check "and nothing was sent" "$([ "$(stub_count)" = 0 ]; echo $?)"
cfg backend=jev points=wrap-7b
out="$(body_run "$(req "$(q p1 backlog-flip-script evil-tool)")")"
jqt "a project .kit.toml cannot widen the allowlist" "$out" '.error == "egress_denied"'
printf '[decide]\ndeny_words = "x"\nbackend = "none"\n' > "$T/cwd/.kit.toml"
out="$(decide_run ok "$IN1")"
jqt "a project .kit.toml cannot switch the backend off or add deny words either (operator wins)" "$out" '.error == "" and .answers.p1.choice == "enhance"'
rm -f "$T/cwd/.kit.toml"
printf '[decide]\nbackend = "jev"\npoints = "wrap-7b"\ndeny_words = "zzprivatecorp"\nword_gate = "off"\n' > "$T/root/kit.toml"
rm -f "$T/op/kit.toml"
out="$(decide_run ok "$IN1")"
jqt "the kit-root kit.toml is read when no operator file exists" "$out" '.error == "" and .backend == "jev"'
rm -f "$T/root/kit.toml"
cfg backend=jev points=wrap-7b
check "the shipped kit.toml has a [decide] block defaulting to backend none" "$(awk '/^\[decide\]/{s=1;next} /^\[/{s=0} s && /^backend *= *"none"/{f=1} END{exit !f}' "$KIT_DIR/kit.toml"; echo $?)"

echo "== post-build fold: hit description in the question text =="
# A fixture kit root: the engine derives KIT_ROOT from its own path, so a copied tree with a
# controlled bin/, commands/ and skills/ pins the description rules without leaning on real kit files.
FX="$T/fxkit"
mkdir -p "$FX/bin" "$FX/lib/decide" "$FX/lib/config" "$FX/lib/alpha" "$FX/commands" "$FX/skills/eps-skill" "$FX/agents"
cp "$KIT_DIR/bin/flick" "$FX/bin/flick"; cp "$KIT_DIR/lib/decide/flick.sh" "$FX/lib/decide/flick.sh"
cp "$KIT_DIR/lib/config/kit-config.sh" "$FX/lib/config/"
printf '#!/usr/bin/env bash\n# bin/alpha-tool -- STABLE consumer entrypoint, never the description\nexec bash "$(dirname "$0")/../lib/alpha/alpha.sh" "$@"\n' > "$FX/bin/alpha-tool"
printf '#!/usr/bin/env bash\n# alpha.sh -- flips backlog rows from a script in one pass.\n# second line must not be used\n' > "$FX/lib/alpha/alpha.sh"
printf '#!/usr/bin/env bash\n#\n# shellcheck disable=SC2034\n# beta-tool lists open pull requests for triage.\necho hi\n' > "$FX/bin/beta-tool"
printf '#!/usr/bin/env bash\nset -e\necho no comment here\n' > "$FX/bin/gamma-tool"
printf -- '---\nname: delta-cmd\ndescription: "Lands the session after the build: merges green PRs."\n---\nbody\n' > "$FX/commands/delta-cmd.md"
printf -- '---\nname: eps-skill\ndescription: Use when auditing manuals against code.\n---\nbody\n' > "$FX/skills/eps-skill/SKILL.md"
printf -- '---\nname: zeta-agent\ndescription: Reviews a diff.\n---\n' > "$FX/agents/zeta-agent.md"
printf '#!/usr/bin/env bash\n# long-tool %s\n' "$(printf 'x%.0s' $(seq 1 300))" > "$FX/bin/long-tool"
printf '#!/usr/bin/env bash\n# ctl-tool: bell\a esc\033[31m tab\there end\r\n' > "$FX/bin/ctl-tool"
chmod +x "$FX/bin/"* "$FX/lib/decide/flick.sh"
cfg backend=jev points=wrap-7b
fxbody() { FLICK_BIN="$FX/bin/flick" FLICK_ARGS=body flick_run ok "$(req "$(q p1 backlog-flip-script "$1")")"; }
out="$(fxbody alpha-tool)"
jqt "bin hit that forwards to lib: the lib header line is the description" "$out" '.questions.q1.instructions | test("flips backlog rows from a script in one pass")'
check "the forwarder's own banner line is not used as the description" "$(grep -q 'STABLE consumer' <<<"$out"; [ $? -ne 0 ]; echo $?)"
out="$(fxbody beta-tool)"
jqt "bin hit without a forward: its first descriptive comment line (shebang and bare # skipped)" "$out" '.questions.q1.instructions | test("beta-tool lists open pull requests for triage")'
check "a shellcheck directive is not a description" "$(grep -q 'shellcheck' <<<"$out"; [ $? -ne 0 ]; echo $?)"
out="$(fxbody delta-cmd)"
jqt "commands hit: description frontmatter, quotes stripped" "$out" '.questions.q1.instructions | test("Lands the session after the build: merges green PRs[.]") and (test("\"") | not)'
out="$(fxbody eps-skill)"
jqt "skills hit: description frontmatter" "$out" '.questions.q1.instructions | test("Use when auditing manuals against code")'
out="$(fxbody zeta-agent)"
jqt "agents hit: description frontmatter" "$out" '.questions.q1.instructions | test("Reviews a diff")'
out="$(fxbody long-tool)"
jqt "description is capped at 160 characters" "$out" '(.questions.q1.instructions | capture("\\(described as: (?<d>.*)\\) cover").d | length) <= 160 and (.questions.q1.instructions | test("xxxx"))'
out="$(fxbody ctl-tool)"
jqt "control characters are stripped from the description" "$out" '(.questions.q1.instructions | explode | any(.[]; . < 32 or . == 127) | not) and (.questions.q1.instructions | test("bell"))'
out="$(fxbody gamma-tool)"
jqt "a hit with no description still works, plain template" "$out" '.questions.q1.instructions == "Does the existing tool gamma-tool cover the job of the candidate backlog-flip-script?"'
cfg backend=jev points=wrap-7b allow_names="extra-public"
out="$(FLICK_BIN="$FX/bin/flick" FLICK_ARGS=body flick_run ok "$(req "$(q p1 backlog-flip-script alpha-tool)" "$(q p2 backlog-flip-script extra-public)")")"
jqt "mixed batch: the described hit carries its text, the allow_names hit has none, both are sent" "$out" '(.questions|keys) == ["q1","q2"] and (.questions.q1.instructions|test("flips backlog rows")) and .questions.q2.instructions == "Does the existing tool extra-public cover the job of the candidate backlog-flip-script?"'
cfg backend=jev points=wrap-7b
echo "-- a description is read from the kit root, never the cwd --"
mkdir -p "$T/plant/bin" "$T/plant/commands" "$T/plant/lib/alpha"
printf '#!/usr/bin/env bash\n# PLANTEDDESC from the cwd bin\n' > "$T/plant/bin/alpha-tool"
printf -- '---\ndescription: PLANTEDDESC from the cwd commands\n---\n' > "$T/plant/commands/delta-cmd.md"
printf '#!/usr/bin/env bash\n# PLANTEDDESC from the cwd lib\n' > "$T/plant/lib/alpha/alpha.sh"
out="$(FLICK_CWD="$T/plant" fxbody alpha-tool)"
jqt "kit-root description is used from a planted cwd" "$out" '.questions.q1.instructions | test("flips backlog rows")'
check "the cwd bin/ lib/ description never reaches the body" "$(grep -q 'PLANTEDDESC' <<<"$out"; [ $? -ne 0 ]; echo $?)"
out="$(FLICK_CWD="$T/plant" fxbody delta-cmd)"
jqt "kit-root commands description is used from a planted cwd" "$out" '.questions.q1.instructions | test("Lands the session after the build")'
check "the cwd commands/ description never reaches the body" "$(grep -q 'PLANTEDDESC' <<<"$out"; [ $? -ne 0 ]; echo $?)"
out="$(body_run "$(req "$(q p1 backlog-flip-script board)" "$(q p2 merge-own-pr-loop wrap)")")"
jqt "real kit: board and wrap each carry a non-empty public description" "$out" '(.questions.q1.instructions|test("tool board \\(described as: .+\\) cover")) and (.questions.q2.instructions|test("tool wrap \\(described as: .+\\) cover"))'
echo "-- per-choice criteria --"
out="$(body_run "$IN1")"
jqt "enhance means the tool already does or could own the job" "$out" '.questions.q1.criteria.enhance | test("already does") and test("could own")'
jqt "new means an unrelated job" "$out" '.questions.q1.criteria.new | test("unrelated job")'

echo "== post-build fold: no egress with an empty deny list =="
cfg backend=jev points=wrap-7b deny_words=
stub_reset; rm -f "$LOG"
out="$(decide_run ok "$IN3")"
jqt "empty deny_words: every question is egress_denied, counted as denied" "$out" '.error == "egress_denied" and .answers == {} and .counts == {"answered":0,"denied":3,"error":0}'
check "empty deny_words: zero requests reach the provider" "$([ "$(stub_count)" = 0 ]; echo $?)"
check "empty deny_words: the log says why (deny_words_empty), one line per question" "$([ "$(wc -l < "$LOG" | tr -d ' ')" = 3 ] && [ "$(jq -r .reason "$LOG" | sort -u)" = deny_words_empty ]; echo $?)"
out="$(body_run "$IN1")"
jqt "empty deny_words: flick body refuses too" "$out" '.error == "egress_denied"'
cfg backend=jev points=wrap-7b deny_words="   "
out="$(decide_run ok "$IN1")"
jqt "a blank deny_words value counts as empty" "$out" '.error == "egress_denied"'
cfg backend=jev points=wrap-7b
out="$(decide_run ok "$IN1")"
jqt "a non-empty deny list sends as before" "$out" '.error == "" and .answers.p1.choice == "enhance"'

echo "== post-build fold: the log dir is root-only =="
LOGHOME="$T/home/.local/state/dwarves-kit/logs"
mkdir -p "$T/projlog" "$T/oplog"
printf '[ledger]\nlocation = "%s"\n' "$T/projlog" > "$T/cwd/.kit.toml"
rm -f "$LOGHOME/decide.jsonl" "$T/projlog/decide.jsonl"
out="$(decide_run ok "$IN1" DWARVES_KIT_LOG_DIR=)"
check "a project [ledger] location does not move decide.jsonl" "$([ ! -e "$T/projlog/decide.jsonl" ]; echo $?)"
check "the log lands in the default dir instead" "$([ -s "$LOGHOME/decide.jsonl" ]; echo $?)"
rm -f "$T/cwd/.kit.toml" "$LOGHOME/decide.jsonl"
{ echo "[decide]"; echo 'backend = "jev"'; echo 'points = "wrap-7b"'; echo 'deny_words = "zzprivatecorp"'; echo 'word_gate = "off"'; echo "[ledger]"; echo "location = \"$T/oplog\""; } > "$T/op/kit.toml"
out="$(decide_run ok "$IN1" DWARVES_KIT_LOG_DIR=)"
check "an operator [ledger] location does move it" "$([ -s "$T/oplog/decide.jsonl" ] && [ ! -e "$LOGHOME/decide.jsonl" ]; echo $?)"
cfg backend=jev points=wrap-7b

echo "== post-build fold: low-severity hardening =="
cfg backend=jev points=wrap-7b timeout_ms=08000
out="$(decide_run ok "$IN1")"
jqt "a zero-padded timeout_ms is read as decimal, not octal" "$out" '.error == "" and .answers.p1.choice == "enhance"'
cfg backend=jev points=wrap-7b
mkdir -p "$T/orphan/bin"; cp "$KIT_DIR/bin/flick" "$T/orphan/bin/flick"
out="$(printf '%s' "$IN1" | "$T/orphan/bin/flick" 2>/dev/null)"; rc=$?
check "bin/flick with the engine missing: exit 0" "$([ "$rc" = 0 ]; echo $?)"
jqt "bin/flick with the engine missing: valid empty-answer JSON" "$out" "$EMPTYJSON and (.error|type==\"string\") and .error != \"\""
stub_reset
mkdir -p "$T/home/.config/dwarves-kit"; command cp -f "$T/op/kit.toml" "$T/home/.config/dwarves-kit/kit.toml"
out="$(decide_run ok "$IN1" FLICK_TEST= HTTPS_PROXY=http://127.0.0.1:1 https_proxy=http://127.0.0.1:1)"
check "FLICK_URL without FLICK_TEST=1 is ignored: the stub saw nothing" "$([ "$(stub_count)" = 0 ]; echo $?)"
jqt "FLICK_URL without FLICK_TEST=1: the call went to the production path (dead proxy, network)" "$out" '.error == "network"'
out="$(decide_run ok "$IN1" FLICK_TEST=0 HTTPS_PROXY=http://127.0.0.1:1 https_proxy=http://127.0.0.1:1)"
jqt "FLICK_TEST=0 is not enough either" "$out" '.error == "network"'
command rm -f "$T/home/.config/dwarves-kit/kit.toml"
rm -f "$LOG"
( umask 022; decide_run ok "$IN1" >/dev/null )
check "the decision log is created owner-only (0600)" "$([ "$(python3 -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$LOG")" = 0o600 ]; echo $?)"

echo "== token_cmd: a second, root-only token source for hosts with no ambient secrets =="
# Helper commands live in $T (no spaces in the path). Each one touches a marker so a test can tell
# whether it ran, and prints a canary that must never show up in stdout, the log or ps.
CMD_TOKEN="CMDTOKEN5e21b9d4"
sha12() { printf '%s' "$1" | python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:12])'; }
mkcmd() { # mkcmd <name> <script-body>
  printf '#!/bin/sh\n: > "%s/ran-%s"\n%s\n' "$T" "$1" "$2" > "$T/cmd-$1"; chmod +x "$T/cmd-$1"
}
mkcmd ok "printf '%s\\n' $CMD_TOKEN"
mkcmd fail "printf '%s\\n' $CMD_TOKEN; exit 3"
mkcmd empty "exit 0"
mkcmd quote "printf '%s\\n' 'abc\"def'"
mkcmd newline "printf 'abc\\ndef\\n'"
mkcmd twonl "printf '%s\\n\\n' $CMD_TOKEN"
mkcmd slow "sleep 40; printf '%s\\n' $CMD_TOKEN"
mkcmd stdin "cat > \"$T/stdin-seen\"; printf '%s\\n' $CMD_TOKEN"
mkcmd argv "printf '%s\\n' \"\$#\" > \"$T/argv-count\"; printf '%s\\n' $CMD_TOKEN"
ran() { [ -e "$T/ran-$1" ]; }
reset_ran() { rm -f "$T"/ran-* "$T/stdin-seen" "$T/argv-count"; }
WANT_SHA="$(sha12 "$CMD_TOKEN")"; ENV_SHA="$(sha12 "$CANARY_TOKEN")"

cfg backend=jev points=wrap-7b jev_token_cmd="$T/cmd-ok"
stub_reset; reset_ran
out="$(decide_run ok "$IN1" JEV_API_TOKEN=)"
jqt "env empty: the token comes from the command and the call is answered" "$out" '.error == "" and .answers.p1.choice == "enhance"'
check "the stub saw the command's token, not another" "$([ "$(cat "$STUB_DIR/authsha.log")" = "$WANT_SHA" ]; echo $?)"
stub_reset; reset_ran
out="$(decide_run ok "$IN1")"
check "env set: the env token is used" "$([ "$(cat "$STUB_DIR/authsha.log")" = "$ENV_SHA" ]; echo $?)"
check "env set: the command never runs" "$(! ran ok; echo $?)"
jqt "env set: answered" "$out" '.error == "" and .answers.p1.choice == "enhance"'

stub_reset; reset_ran
cfg backend=jev points=wrap-7b jev_token_cmd="$T/cmd-fail"
out="$(decide_run ok "$IN1" JEV_API_TOKEN=)"
jqt "a failing command: no_token, counts error" "$out" '.error == "no_token" and .counts.error == 1 and .answers == {}'
check "a failing command that printed a token sends nothing" "$([ "$(stub_count)" = 0 ] && ran fail; echo $?)"
cfg backend=jev points=wrap-7b jev_token_cmd="$T/cmd-empty"
out="$(decide_run ok "$IN1" JEV_API_TOKEN=)"
jqt "a command that prints nothing: no_token" "$out" '.error == "no_token"'
cfg backend=jev points=wrap-7b jev_token_cmd="$T/cmd-no-such-file"
out="$(decide_run ok "$IN1" JEV_API_TOKEN=)"
jqt "a command that does not exist: no_token, exit 0" "$out" '.error == "no_token"'
for c in quote newline twonl; do
  cfg backend=jev points=wrap-7b jev_token_cmd="$T/cmd-$c"
  stub_reset
  out="$(decide_run ok "$IN1" JEV_API_TOKEN=)"
  jqt "command output failing the shape check ($c): no_token" "$out" '.error == "no_token"'
  check "shape-check failure ($c) sent nothing" "$([ "$(stub_count)" = 0 ]; echo $?)"
done

echo "-- the command is bounded, shell-free and silent --"
cfg backend=jev points=wrap-7b jev_token_cmd="$T/cmd-slow"
stub_reset
t0="$(ms_now)"; out="$(decide_run ok "$IN1" JEV_API_TOKEN=)"; t1="$(ms_now)"
jqt "a slow command: no_token" "$out" '.error == "no_token"'
check "the slow command was cut off at about 10 s (not 40)" "$([ $((t1-t0)) -ge 9500 ] && [ $((t1-t0)) -lt 15000 ]; echo $?)" "took $((t1-t0)) ms"
cfg backend=jev points=wrap-7b jev_token_cmd="$T/cmd-stdin"
reset_ran; echo "stdin-should-not-be-read" > "$T/feed"
out="$(printf '%s' "$IN1" | ( cd "$T/cwd" && env -i PATH="$PATH" HOME="$T/home" KIT_CONFIG_ROOT="$T/root" KIT_CONFIG_OPERATOR="$T/op" KIT_PROJECT_ROOT="$T/cwd" DWARVES_KIT_LOG_DIR="$T/log" FLICK_TEST=1 FLICK_URL="http://127.0.0.1:${PORT}/ok" "$FLICK" decide 2>/dev/null ))"
jqt "the command reads stdin from /dev/null, not flick's request" "$out" '.error == ""'
check "the command saw an empty stdin" "$([ -f "$T/stdin-seen" ] && [ ! -s "$T/stdin-seen" ]; echo $?)"
echo "-- no expansion: glob, command substitution, quotes --"
mkdir -p "$T/globdir"; : > "$T/globdir/a" ; : > "$T/globdir/b"
cfg backend=jev points=wrap-7b jev_token_cmd="$T/cmd-argv $T/globdir/* \$(touch $T/subst-ran) \`touch $T/bt-ran\` ;touch $T/semi-ran"
reset_ran
out="$(decide_run ok "$IN1" JEV_API_TOKEN=)"
check "the glob was passed literally: argv count is the 7 literal words" "$([ "$(cat "$T/argv-count" 2>/dev/null)" = 7 ]; echo $?)" "argc=$(cat "$T/argv-count" 2>/dev/null)"
check "no command substitution, backtick or semicolon ran anything" "$([ ! -e "$T/subst-ran" ] && [ ! -e "$T/bt-ran" ] && [ ! -e "$T/semi-ran" ]; echo $?)"
echo "-- the output never leaks --"
cfg backend=jev points=wrap-7b jev_token_cmd="$T/cmd-ok"
rm -f "$LOG"; stub_reset
out="$(decide_run ok "$IN1" JEV_API_TOKEN=)"
check "the command's token is not in stdout, the log or the stub body" "$(grep -q "$CMD_TOKEN" "$LOG" "$STUB_DIR/bodies.log" <<<"$out"; [ $? -ne 0 ] && ! grep -q "$CMD_TOKEN" "$LOG" "$STUB_DIR/bodies.log"; echo $?)"
cfg backend=jev points=wrap-7b jev_token_cmd="$T/cmd-ok"
( decide_run slow "$IN1" JEV_API_TOKEN= >/dev/null ) &
SLOWPID=$!
ps_all=""; ps_n=0
while [ "$ps_n" -lt 60 ]; do
  ps_all="$ps_all
$(ps -A -o args= 2>/dev/null)"
  grep -q 'curl .*--config' <<<"$ps_all" && break
  sleep 0.1; ps_n=$((ps_n+1))
done
check "ps shows no command token while curl is in flight" "$(grep -q "$CMD_TOKEN" <<<"$ps_all"; [ $? -ne 0 ]; echo $?)"
check "ps shows curl really was in flight (the check is not vacuous)" "$(grep -q 'curl .*--config' <<<"$ps_all"; echo $?)"
wait "$SLOWPID"

echo "-- token_cmd is root-only --"
cfg backend=jev points=wrap-7b
printf '[decide]\njev_token_cmd = "%s/cmd-ok"\n' "$T" > "$T/cwd/.kit.toml"
reset_ran; stub_reset
out="$(decide_run ok "$IN1" JEV_API_TOKEN=)"
jqt "a project .kit.toml token_cmd is ignored: no_token" "$out" '.error == "no_token"'
check "the project command never ran and nothing was sent" "$(! ran ok && [ "$(stub_count)" = 0 ]; echo $?)"
rm -f "$T/cwd/.kit.toml"
printf '[decide]\nbackend = "jev"\npoints = "wrap-7b"\ndeny_words = "zzprivatecorp"\nword_gate = "off"\njev_token_cmd = "%s/cmd-ok"\n' "$T" > "$T/root/kit.toml"
rm -f "$T/op/kit.toml"
out="$(decide_run ok "$IN1" JEV_API_TOKEN=)"
jqt "the kit-root kit.toml token_cmd is read when no operator file exists" "$out" '.error == ""'
rm -f "$T/root/kit.toml"
cfg backend=jev points=wrap-7b

echo "== token_cmd hardening: env injection, TERM-proof, descendants, output cap, absolute path =="
mkcmd trapterm "trap '' TERM; while :; do :; done"
mkcmd orphan "printf '%s\\n' $CMD_TOKEN; (sleep 27) >/dev/null 2>&1 &"
mkcmd bigfinite "head -c 5000 /dev/zero | tr '\\0' a"
mkcmd bigforever "exec yes aaaaaaaaaaaaaaaa"
echo "-- env vars cannot inject config (the engine's own variable namespaces) --"
cfg backend=jev points=wrap-7b
reset_ran; stub_reset
out="$(decide_run ok "$IN1" JEV_API_TOKEN= "OP_jev_token_cmd=$T/cmd-ok")"
jqt "env OP_jev_token_cmd has no effect: no_token" "$out" '.error == "no_token"'
check "env OP_jev_token_cmd never ran a command" "$(! ran ok; echo $?)"
out="$(decide_run ok "$IN1" JEV_API_TOKEN= "RT_jev_token_cmd=$T/cmd-ok")"
check "env RT_jev_token_cmd never ran a command" "$(! ran ok; echo $?)"
out="$(decide_run ok "$IN1" JEV_API_TOKEN= "FLKC_OP_jev_token_cmd=$T/cmd-ok" "FLKC_RT_jev_token_cmd=$T/cmd-ok")"
check "env under the engine's private prefix never ran a command" "$(! ran ok; echo $?)"
rm -f "$T/op/kit.toml"
out="$(decide_run ok "$IN1" RT_backend=jev OP_backend=jev)"
jqt "env RT_backend and OP_backend cannot switch the backend on" "$out" '.error == "backend_none"'
cfg backend=jev points="" deny_words=zzprivatecorp
out="$(decide_run ok "$IN1" OP_points=wrap-7b RT_points=wrap-7b)"
jqt "env OP_points cannot enable a point" "$out" '.error == "point_disabled"'
cfg backend=jev points=wrap-7b deny_words=
stub_reset
out="$(decide_run ok "$IN1" OP_deny_words=zzprivatecorp RT_deny_words=zzprivatecorp)"
jqt "env OP_deny_words cannot fill an empty deny list" "$out" '.error == "egress_denied"'
check "and nothing was sent" "$([ "$(stub_count)" = 0 ]; echo $?)"
cfg backend=jev points=wrap-7b
out="$(body_run "$(req "$(q p1 backlog-flip-script evil-tool)")" OP_allow_names=evil-tool RT_allow_names=evil-tool)"
jqt "env OP_allow_names cannot widen the allowlist" "$out" '.error == "egress_denied"'

echo "-- a command that ignores TERM, leaves descendants, or floods output --"
cfg backend=jev points=wrap-7b jev_token_cmd="$T/cmd-trapterm"
t0="$(ms_now)"; out="$(decide_run ok "$IN1" JEV_API_TOKEN=)"; t1="$(ms_now)"
jqt "a TERM-ignoring command: no_token, valid JSON, exit 0" "$out" '.error == "no_token" and .counts.error == 1'
check "a TERM-ignoring command was escalated and flick returned inside the limit plus grace" "$([ $((t1-t0)) -ge 9500 ] && [ $((t1-t0)) -lt 16000 ]; echo $?)" "took $((t1-t0)) ms"
check "no spinning command is left behind" "$(! pgrep -f "$T/cmd-trapterm" >/dev/null; echo $?)"
cfg backend=jev points=wrap-7b jev_token_cmd="$T/cmd-orphan"
stub_reset
t0="$(ms_now)"; out="$(decide_run ok "$IN1" JEV_API_TOKEN=)"; t1="$(ms_now)"
jqt "a command that leaves a background child: the token is still used" "$out" '.error == "" and .answers.p1.choice == "enhance"'
check "a lingering descendant did not hold flick open (returned well inside 27 s)" "$([ $((t1-t0)) -lt 12000 ]; echo $?)" "took $((t1-t0)) ms"
check "the descendant was killed with its group" "$(! pgrep -f 'sleep 27' >/dev/null; echo $?)"
for big in bigfinite bigforever; do
  cfg backend=jev points=wrap-7b jev_token_cmd="$T/cmd-$big"
  stub_reset
  t0="$(ms_now)"; out="$(decide_run ok "$IN1" JEV_API_TOKEN=)"; t1="$(ms_now)"
  jqt "oversized command output ($big): no_token" "$out" '.error == "no_token"'
  check "oversized output ($big) sent nothing and finished in bounded time" "$([ "$(stub_count)" = 0 ] && [ $((t1-t0)) -lt 16000 ]; echo $?)" "took $((t1-t0)) ms"
done
check "no token temp dir is left behind" "$(! ls -d /tmp/flick.* >/dev/null 2>&1; echo $?)"

echo "-- the command's first word must be an absolute path --"
reset_ran
cfg backend=jev points=wrap-7b jev_token_cmd="cmd-ok"
out="$(FLICK_CWD="$T" decide_run ok "$IN1" JEV_API_TOKEN= "PATH=$T:$PATH")"
jqt "a bare command name is refused: no_token" "$out" '.error == "no_token"'
check "the bare-name command never ran" "$(! ran ok; echo $?)"
cfg backend=jev points=wrap-7b jev_token_cmd="./cmd-ok"
out="$(FLICK_CWD="$T" decide_run ok "$IN1" JEV_API_TOKEN=)"
jqt "a relative path is refused: no_token" "$out" '.error == "no_token"'
check "the relative-path command never ran" "$(! ran ok; echo $?)"
cfg backend=jev points=wrap-7b

echo "== word gate: each hyphen segment of a candidate must be a dictionary word, a dev word, or a public name =="
# A small fixture dictionary, so the tests never depend on the host's. "Widget" is capitalized on
# purpose: the match is case-insensitive.
WG_DICT="$T/fixture-words"
printf '%s\n' backlog flip script Widget sync helper loft > "$WG_DICT"
# wg_cfg <key=value>...: operator [decide] block WITHOUT a word_gate key (the shipped default),
# pointing the dictionary at the fixture unless the caller passes dict_file=.
wg_cfg() {
  local kv hasdict=0
  { echo "[decide]"; echo 'backend = "jev"'; echo 'points = "wrap-7b"'
    for kv in "$@"; do case "$kv" in dict_file=*) hasdict=1 ;; esac; echo "${kv%%=*} = \"${kv#*=}\""; done
    [ "$hasdict" = 1 ] || echo "dict_file = \"$WG_DICT\""
    case " $* " in *" deny_words="*) ;; *) echo 'deny_words = "zzprivatecorp"' ;; esac; } > "$T/op/kit.toml"
}
WGNAME=zorbix   # a made-up name: in no dictionary, no dev-word list, no public set

wg_cfg
out="$(body_run "$(req "$(q p1 backlog-flip-script board)")")"
jqt "generic slug (every segment a dictionary word) passes" "$out" '(.questions|keys) == ["q1"]'
out="$(body_run "$(req "$(q p1 "$WGNAME-sync" board)")")"
jqt "a made-up name segment is denied (the shipped default is on)" "$out" '.error == "egress_denied" and .answers == {} and .counts == {"answered":0,"denied":1,"error":0}'
check "the made-up name is absent from the flick body output" "$(grep -q "$WGNAME" <<<"$out"; [ $? -ne 0 ]; echo $?)"
stub_reset; rm -f "$LOG"
out="$(decide_run ok "$(req "$(q p1 "$WGNAME-sync" board)")")"
jqt "decide: the made-up name is egress_denied" "$out" '.error == "egress_denied" and .answers == {}'
check "decide: zero requests reach the provider" "$([ "$(stub_count)" = 0 ]; echo $?)"
check "the log reason is word_gate and the name is not logged" "$([ "$(jq -r .reason "$LOG")" = word_gate ] && ! grep -q "$WGNAME" "$LOG"; echo $?)"

out="$(body_run "$(req "$(q p1 pr-ci-api-cli-json-yaml board)" "$(q p2 git-gh-repo-env-url-sdk wrap)" "$(q p3 todo-wip-config-auth-regex board)" "$(q p4 stdin-stdout-async-diff-lint board)")")"
jqt "built-in dev words pass without being in the dictionary" "$out" '(.questions|keys) == ["q1","q2","q3","q4"]'

out="$(body_run "$(req "$(q p1 board-sync board)" "$(q p2 wrap-script board)")")"
jqt "a kit-public name segment passes without being in the dictionary" "$out" '(.questions|keys) == ["q1","q2"]'
wg_cfg allow_names=extrapub
out="$(body_run "$(req "$(q p1 extrapub-sync board)" "$(q p2 extrap-sync board)")")"
jqt "an allow_names entry counts as public for a segment, a partial one does not" "$out" '(.questions|keys) == ["q1"]'

wg_cfg
out="$(body_run "$(req "$(q p1 widget-sync board)")")"
jqt "dictionary match is case-insensitive (fixture holds Widget)" "$out" '(.questions|keys) == ["q1"]'
out="$(body_run "$(req "$(q p1 "$WGNAME" board)" "$(q p2 "backlog-$WGNAME" board)" "$(q p3 "$WGNAME-flip" board)")")"
jqt "denied wherever the unknown segment sits: alone, last, first" "$out" '.error == "egress_denied" and .counts.denied == 3'
out="$(body_run "$(req "$(q p1 backlog--flip board)")")"
jqt "an empty segment (double hyphen) is not a word, and not a failure" "$out" '(.questions|keys) == ["q1"]'

out="$(body_run "$(req "$(q p1 --- board)")")"
jqt "a slug with no word at all is denied" "$out" '.error == "egress_denied"'

echo "-- dictionary file failures fail closed --"
for df in "$T/no-such-words" "$T"; do
  wg_cfg dict_file="$df"
  stub_reset; rm -f "$LOG"
  out="$(decide_run ok "$(req "$(q p1 backlog-flip-script board)" "$(q p2 pr-ci board)")")"
  jqt "dict_file '${df##*/}' unusable: every candidate egress_denied, even all-dictionary ones" "$out" '.error == "egress_denied" and .answers == {} and .counts == {"answered":0,"denied":2,"error":0}'
  check "dict_file '${df##*/}' unusable: zero requests, log reason word_gate_no_dict" "$([ "$(stub_count)" = 0 ] && [ "$(jq -r .reason "$LOG" | sort -u)" = word_gate_no_dict ]; echo $?)"
done
: > "$T/empty-words"
wg_cfg dict_file="$T/empty-words"
out="$(body_run "$(req "$(q p1 backlog-flip-script board)")")"
jqt "an empty dictionary denies every non-dev, non-public segment" "$out" '.error == "egress_denied"'

echo "-- one dictionary pass per batch --"
mkdir -p "$T/shim"
printf '#!/bin/sh\necho x >> "%s/awk-calls"\nexec "%s" "$@"\n' "$T" "$(command -v awk)" > "$T/shim/awk"; chmod +x "$T/shim/awk"
wg_cfg
: > "$T/awk-calls"
big="$(jq -nc '{point:"wrap-7b",questions:[range(0;50)|{id:"p\(.)",candidate:(if . % 2 == 0 then "backlog-flip-script" else "zorbix-sync" end),hit:"board"}]}')"
out="$(body_run "$big" "PATH=$T/shim:$PATH")"
jqt "a 50-question batch: the 25 dictionary slugs pass, the 25 made-up ones drop" "$out" '(.questions|length) == 25'
check "the whole batch used exactly one dictionary pass" "$([ "$(wc -l < "$T/awk-calls" | tr -d ' ')" = 1 ]; echo $?)"

out=""; flaky=0
for _ in $(seq 1 25); do
  out="$(body_run "$(req "$(q p1 backlog-flip-script board)")")"
  jq -e '(.questions|keys) == ["q1"]' >/dev/null 2>&1 <<<"$out" || flaky=$((flaky+1))
done
check "25 repeated runs agree: the dictionary pass never crashes into word_gate_no_dict" "$([ "$flaky" = 0 ]; echo $?)" "$flaky of 25 differed"

echo "-- short segments never pass by dictionary (single letters are dictionary words) --"
printf '%s\n' a b c e i m o r x z sync Widget > "$T/letters-words"
wg_cfg dict_file="$T/letters-words"
for slug in z-o-r-b-i-x-sync a-c-m-e-sync; do
  stub_reset
  out="$(decide_run ok "$(req "$(q p1 "$slug" board)")")"
  jqt "spelled-out slug $slug is egress_denied" "$out" '.error == "egress_denied" and .answers == {}'
  check "spelled-out slug $slug: zero requests" "$([ "$(stub_count)" = 0 ]; echo $?)"
  out="$(body_run "$(req "$(q p1 "$slug" board)")")"
  check "spelled-out slug $slug is absent from the body" "$(grep -q "$slug" <<<"$out"; [ $? -ne 0 ]; echo $?)"
done
out="$(body_run "$(req "$(q p1 pr-ci-db-ai-id board)" "$(q p2 ab-sync board)")")"
jqt "two-letter dev words still pass; a two-letter non-dev segment is denied" "$out" '(.questions|keys) == ["q1"]'
wg_cfg allow_names=zq
out="$(body_run "$(req "$(q p1 zq-sync board)")")"
jqt "a short segment that is a kit-public name still passes" "$out" '.questions|keys == ["q1"]'

echo "-- dict_file must be an absolute path to a regular file under 16 MB --"
mkdir -p "$T/dictcwd"; command cp -f "$WG_DICT" "$T/dictcwd/rel-words"
python3 -c 'import sys;open(sys.argv[1],"wb").truncate(17*1024*1024)' "$T/huge-words"
for df in "rel-words" "./rel-words" "$T/huge-words" "$T/dictcwd/../dictcwd/missing"; do
  wg_cfg dict_file="$df"
  stub_reset; rm -f "$LOG"
  out="$(FLICK_CWD="$T/dictcwd" decide_run ok "$(req "$(q p1 backlog-flip-script board)")")"
  jqt "dict_file '${df##*/}' (relative, oversize or missing): egress_denied" "$out" '.error == "egress_denied" and .answers == {}'
  check "dict_file '${df##*/}': zero requests, reason word_gate_no_dict" "$([ "$(stub_count)" = 0 ] && [ "$(jq -r .reason "$LOG" | sort -u)" = word_gate_no_dict ]; echo $?)"
done
wg_cfg dict_file="$T/dictcwd/rel-words"
out="$(FLICK_CWD="$T/dictcwd" body_run "$(req "$(q p1 backlog-flip-script board)")")"
jqt "the same file by absolute path works" "$out" '(.questions|keys) == ["q1"]'

echo "-- config location: env cannot choose the config files without FLICK_TEST=1 --"
mkdir -p "$T/envop" "$T/envroot" "$T/xdg/dwarves-kit" "$T/home/.config/dwarves-kit" "$T/dwk"
EVIL='[decide]
backend = "jev"
points = "wrap-7b"
word_gate = "off"
deny_words = "zzother"
'
printf '%s' "$EVIL" > "$T/envop/kit.toml"; printf '%s' "$EVIL" > "$T/envroot/kit.toml"
printf '%s' "$EVIL" > "$T/xdg/dwarves-kit/kit.toml"; printf '%s' "$EVIL" > "$T/dwk/kit.toml"
rm -f "$T/op/kit.toml" "$T/root/kit.toml" "$T/home/.config/dwarves-kit/kit.toml"
for pair in "KIT_CONFIG_OPERATOR=$T/envop" "KIT_CONFIG_ROOT=$T/envroot" "XDG_CONFIG_HOME=$T/xdg" "DWARVES_KIT=$T/dwk"; do
  stub_reset
  out="$(decide_run ok "$(req "$(q p1 "$WGNAME-sync" board)")" FLICK_TEST= KIT_CONFIG_OPERATOR= KIT_CONFIG_ROOT= "$pair")"
  jqt "${pair%%=*} without FLICK_TEST=1 changes nothing (backend stays none)" "$out" '.error == "backend_none"'
  check "${pair%%=*} without FLICK_TEST=1: nothing was sent" "$([ "$(stub_count)" = 0 ]; echo $?)"
done
out="$(decide_run ok "$(req "$(q p1 "$WGNAME-sync" board)")" FLICK_TEST= KIT_CONFIG_OPERATOR="$T/envop" KIT_CONFIG_ROOT="$T/envroot" XDG_CONFIG_HOME="$T/xdg" DWARVES_KIT="$T/dwk")"
jqt "all four together: still backend_none" "$out" '.error == "backend_none"'
printf '[decide]\nbackend = "jev"\npoints = "wrap-7b"\ndeny_words = "zzprivatecorp"\ndict_file = "%s"\n' "$WG_DICT" > "$T/home/.config/dwarves-kit/kit.toml"
out="$(FLICK_ARGS=body flick_run ok "$(req "$(q p1 "$WGNAME-sync" board)" "$(q p2 backlog-flip-script board)")" FLICK_TEST= KIT_CONFIG_OPERATOR="$T/envop" KIT_CONFIG_ROOT="$T/envroot")"
jqt "production reads \$HOME/.config/dwarves-kit/kit.toml, gate on, env ignored" "$out" '(.questions|keys) == ["q1"]'
out="$(FLICK_ARGS=body flick_run ok "$(req "$(q p1 "$WGNAME-sync" board)" "$(q p2 backlog-flip-script board)")" KIT_CONFIG_OPERATOR="$T/envop" KIT_CONFIG_ROOT="$T/envroot")"
jqt "with FLICK_TEST=1 the env does choose the files (the test hook works)" "$out" '(.questions|keys) == ["q1","q2"]'
command rm -f "$T/home/.config/dwarves-kit/kit.toml"
cfg backend=jev points=wrap-7b

echo "-- deny_words still applies on top --"
wg_cfg deny_words=loft
out="$(body_run "$(req "$(q p1 loft-script board)" "$(q p2 backlog-script board)")")"
jqt "a dictionary word on the deny list is still denied" "$out" '(.questions|keys) == ["q1"] and (.questions.q1.instructions|test("candidate backlog-script"))'

echo "-- mixed batch --"
wg_cfg
stub_reset; rm -f "$LOG"
out="$(body_run "$(req "$(q p1 backlog-flip-script board)" "$(q p2 "$WGNAME-plan" board)" "$(q p3 sync-helper wrap)")")"
jqt "mixed batch: the allowed questions stay, renumbered q1 q2" "$out" '(.questions|keys) == ["q1","q2"] and (.questions.q1.instructions|test("candidate backlog-flip-script")) and (.questions.q2.instructions|test("candidate sync-helper"))'
check "mixed batch: the denied name is absent from the body" "$(grep -q "$WGNAME" <<<"$out"; [ $? -ne 0 ]; echo $?)"
out="$(decide_run ok "$(req "$(q p1 backlog-flip-script board)" "$(q p2 "$WGNAME-plan" board)" "$(q p3 sync-helper wrap)")")"
jqt "mixed batch: decide counts 2 answered, 1 denied, and answers the allowed ids" "$out" '.error == "" and .counts == {"answered":2,"denied":1,"error":0} and (.answers.p1.choice == "enhance") and (.answers.p2.error == "egress_denied") and (.answers.p3.choice != "")'
check "mixed batch: one request, the log marks the denied row word_gate" "$([ "$(stub_count)" = 1 ] && [ "$(jq -r 'select(.index == 1) | .reason' "$LOG")" = word_gate ]; echo $?)"

echo "-- word_gate = off restores the old behaviour --"
wg_cfg word_gate=off
out="$(body_run "$(req "$(q p1 "$WGNAME-sync" board)")")"
jqt "word_gate off: the made-up name passes the word gate (deny_words still applies)" "$out" '(.questions|keys) == ["q1"]'
wg_cfg word_gate=off dict_file="$T/no-such-words"
out="$(body_run "$(req "$(q p1 "$WGNAME-sync" board)")")"
jqt "word_gate off: a missing dictionary does not matter" "$out" '(.questions|keys) == ["q1"]'
wg_cfg word_gate=maybe
out="$(body_run "$(req "$(q p1 "$WGNAME-sync" board)")")"
jqt "an unrecognised word_gate value is treated as on" "$out" '.error == "egress_denied"'

echo "-- root-only: a project .kit.toml cannot weaken the gate --"
wg_cfg
printf '[decide]\nword_gate = "off"\ndict_file = "%s"\n' "$T/project-words" > "$T/cwd/.kit.toml"
printf '%s\n' "$WGNAME" sync > "$T/project-words"
out="$(body_run "$(req "$(q p1 "$WGNAME-sync" board)")")"
jqt "a project .kit.toml cannot turn word_gate off or swap the dictionary" "$out" '.error == "egress_denied"'
rm -f "$T/cwd/.kit.toml"
printf '[decide]\nbackend = "jev"\npoints = "wrap-7b"\ndeny_words = "zzprivatecorp"\ndict_file = "%s"\n' "$WG_DICT" > "$T/root/kit.toml"
rm -f "$T/op/kit.toml"
out="$(body_run "$(req "$(q p1 "$WGNAME-sync" board)" "$(q p2 backlog-flip-script board)")")"
jqt "the kit-root kit.toml supplies dict_file and the default-on gate" "$out" '(.questions|keys) == ["q1"]'
rm -f "$T/root/kit.toml"

echo "-- the host dictionary (skipped when absent) --"
if [ -r /usr/share/dict/words ]; then
  wg_cfg dict_file=/usr/share/dict/words
  out="$(body_run "$(req "$(q p1 backlog-flip-script board)" "$(q p2 merge-loop-helper board)" "$(q p3 "$WGNAME-sync" board)")")"
  jqt "host dictionary: generic slugs pass, the made-up name is denied" "$out" '(.questions|keys) == ["q1","q2"]'
  printf '[decide]\nbackend = "jev"\npoints = "wrap-7b"\ndeny_words = "zzprivatecorp"\n' > "$T/op/kit.toml"
  out="$(body_run "$(req "$(q p1 backlog-flip-script board)")")"
  jqt "dict_file defaults to /usr/share/dict/words" "$out" '(.questions|keys) == ["q1"]'
else
  echo "  SKIP: /usr/share/dict/words not present"
fi
cfg backend=jev points=wrap-7b

# --- sections above; summary below ---
echo
echo "flick: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
