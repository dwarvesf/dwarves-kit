#!/usr/bin/env bash
# build-cases.sh -- writes cases.jsonl for the context-hints parity test. Each case is one
# JSON line the shared harness (tests/lib/hook-parity.sh) runs: name, env, payload, optional
# seed (files written first) and read (files dumped after). The state dir is @HOME@/st so a
# case can seed and read it. Cases whose Python behavior is a swallowed crash carry the
# comment "crash" in their name; the port exits 0 silently there, like the Python shim.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/cases.jsonl"
: > "$OUT"

# add <name> <env-json> <payload-json-or-RAW:text> [seed-json] [read-json]
add() {
  local name="$1" env="$2" payload="$3" seed="${4:-}" read="${5:-}"
  [ -n "$seed" ] || seed='{}'
  [ -n "$read" ] || read='[]'
  if [[ "$payload" == RAW:* ]]; then
    jq -c -n --arg n "$name" --argjson e "$env" --arg p "$payload" --argjson s "$seed" --argjson r "$read" \
      '{name:$n, env:$e, payload:$p, seed:$s, read:$r}' >> "$OUT"
  else
    jq -c -n --arg n "$name" --argjson e "$env" --argjson p "$payload" --argjson s "$seed" --argjson r "$read" \
      '{name:$n, env:$e, payload:$p, seed:$s, read:$r}' >> "$OUT"
  fi
}

ST='"CONTEXT_HINTS_STATE":"@HOME@/st"'
env_at() { printf '{%s,"CONTEXT_HINTS_NOW":"%s"%s}' "$ST" "$1" "${2:+,$2}"; }
state() { printf '{"start":%s,"last":%s}' "$1" "$2"; }
seed_state() { jq -c -n --arg sid "$1" --arg body "$2" '{("home/st/" + $sid + ".json"): $body}'; }
read_state() { printf '["home/st/%s.json"]' "$1"; }
MAP='"CONTEXT_HINTS_SKILLMAP":"@HOME@/map.json"'
seed_map() { jq -c -n --arg body "$1" '{"home/map.json": $body}'; }
seed_both() { jq -c -n --arg sid "$1" --arg st "$2" --arg map "$3" '{("home/st/" + $sid + ".json"): $st, "home/map.json": $map}'; }

# --- the temporal line ---
add first-prompt-silent "$(env_at 1000)" '{"prompt":"hi","session_id":"s1"}' '{}' "$(read_state s1)"
add second-prompt-line "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000.0 1000.0)")" "$(read_state s1)"
add seconds-only "$(env_at 1030)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add minutes-pad "$(env_at 1065)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000 1060)")" "$(read_state s1)"
add hours-pad "$(env_at 8500)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000 8000)")" "$(read_state s1)"
add elapsed-just-under-one "$(env_at 1000.9)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add elapsed-exactly-one "$(env_at 1001)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add float-now "$(env_at 1090.75)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000.25 1050.5)")" "$(read_state s1)"
add nudge-at-threshold "$(env_at 22600)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000 22000)")" "$(read_state s1)"
add nudge-just-over "$(env_at 22601)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000 22000)")" "$(read_state s1)"
add nudge-with-hints "$(env_at 30000 "$MAP")" '{"prompt":"run the ocr job","session_id":"s1"}' "$(seed_both s1 "$(state 1000 29000)" '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add idle-negative "$(env_at 1500)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000 2000)")" "$(read_state s1)"
add temporal-off "$(env_at 1100 '"CONTEXT_HINTS_TEMPORAL":"0"')" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add temporal-off-with-hints "$(env_at 1100 "\"CONTEXT_HINTS_TEMPORAL\":\"0\",$MAP")" '{"prompt":"ocr","session_id":"s1"}' "$(seed_both s1 "$(state 1000 1000)" '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add temporal-one-is-on "$(env_at 1100 '"CONTEXT_HINTS_TEMPORAL":"1"')" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add temporal-empty-is-on "$(env_at 1100 '"CONTEXT_HINTS_TEMPORAL":""')" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add now-empty-uses-clock '{"CONTEXT_HINTS_STATE":"@HOME@/st","CONTEXT_HINTS_NOW":""}' '{"prompt":"hi","session_id":"s1"}' '{}' '[]'
add now-unset-uses-clock '{"CONTEXT_HINTS_STATE":"@HOME@/st"}' '{"prompt":"hi","session_id":"s1"}' '{}' '[]'
add crash-now-garbage "$(env_at abc)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add now-padded-spaces "$(env_at ' 1100 ')" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"

# --- the state file ---
add state-default-dir '{"CONTEXT_HINTS_NOW":"1100"}' '{"prompt":"hi","session_id":"s1"}' '{"home/.claude/dwarves-kit/state/context-hints/s1.json":"{\"start\": 1000.0, \"last\": 1000.0}"}' '["home/.claude/dwarves-kit/state/context-hints/s1.json"]'
add state-default-dir-first '{"CONTEXT_HINTS_NOW":"1100"}' '{"prompt":"hi","session_id":"s1"}' '{}' '["home/.claude/dwarves-kit/state/context-hints/s1.json"]'
add state-corrupt "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 'garbage')" "$(read_state s1)"
add state-empty-file "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 '')" "$(read_state s1)"
add state-trailing-garbage "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 '{"start":1000,"last":1000} x')" "$(read_state s1)"
add crash-state-list "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 '[1,2]')" "$(read_state s1)"
add crash-state-null "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 'null')" "$(read_state s1)"
add crash-state-number "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 '5')" "$(read_state s1)"
add state-empty-object "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 '{}')" "$(read_state s1)"
add state-start-only "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 '{"start":1000}')" "$(read_state s1)"
add state-last-only "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 '{"last":1000}')" "$(read_state s1)"
add state-start-bad-string "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 '{"start":"abc","last":1000}')" "$(read_state s1)"
add state-numeric-strings "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 '{"start":"1000","last":"1050"}')" "$(read_state s1)"
add state-bool-start "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 '{"start":true,"last":1050}')" "$(read_state s1)"
add crash-state-last-null "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 '{"start":1000,"last":null}')" "$(read_state s1)"
add crash-state-start-null "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 '{"start":null,"last":1000}')" "$(read_state s1)"
add state-bad-start-null-last "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 '{"start":"abc","last":null}')" "$(read_state s1)"
add state-extra-keys-dropped "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 '{"start":1000,"last":1000,"extra":"x"}')" "$(read_state s1)"
add state-dir-empty '{"CONTEXT_HINTS_STATE":"","CONTEXT_HINTS_NOW":"1100"}' '{"prompt":"hi","session_id":"s1"}' '{"cwd/s1.json":"{\"start\":1000,\"last\":1000}"}' '["cwd/s1.json"]'
add state-dir-is-a-file '{"CONTEXT_HINTS_STATE":"@HOME@/f/st","CONTEXT_HINTS_NOW":"1100"}' '{"prompt":"hi","session_id":"s1"}' '{"home/f":"x"}' '[]'
add state-path-is-a-directory "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' '{"home/st/s1.json/keep":"x"}' '[]'
add state-two-sessions "$(env_at 1100)" '{"prompt":"hi","session_id":"s2"}' "$(seed_state s1 "$(state 1000 1000)")" '["home/st/s1.json","home/st/s2.json"]'

# --- the payload ---
add empty-stdin "$(env_at 1100)" 'RAW:'
add not-json "$(env_at 1100)" 'RAW:not json'
add json-list "$(env_at 1100)" 'RAW:[]'
add json-string "$(env_at 1100)" 'RAW:"hi"'
add json-null "$(env_at 1100)" 'RAW:null'
add json-number "$(env_at 1100)" 'RAW:5'
add two-objects "$(env_at 1100)" 'RAW:{"prompt":"a"} {"prompt":"b"}'
add trailing-garbage "$(env_at 1100)" 'RAW:{"prompt":"a"} x'
add whitespace-only "$(env_at 1100)" 'RAW:   '
add empty-object "$(env_at 1100)" '{}' "$(seed_state default "$(state 1000 1000)")" '["home/st/default.json"]'
add prompt-last-prompt "$(env_at 1100 "$MAP")" '{"lastPrompt":"need ocr here","session_id":"s1"}' "$(seed_both s1 "$(state 1000 1000)" '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add prompt-empty-falls-to-last "$(env_at 1100 "$MAP")" '{"prompt":"","lastPrompt":"need ocr here","session_id":"s1"}' "$(seed_both s1 "$(state 1000 1000)" '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add prompt-beats-last-prompt "$(env_at 1100 "$MAP")" '{"prompt":"hello","lastPrompt":"need ocr here","session_id":"s1"}' "$(seed_both s1 "$(state 1000 1000)" '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add crash-prompt-number "$(env_at 1100)" '{"prompt":5,"session_id":"s1"}' "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add crash-prompt-list "$(env_at 1100)" '{"prompt":["ocr"],"session_id":"s1"}' "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add crash-prompt-true "$(env_at 1100)" '{"prompt":true,"session_id":"s1"}' "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add prompt-zero-is-empty "$(env_at 1100)" '{"prompt":0,"session_id":"s1"}' "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add prompt-blank "$(env_at 1100 "$MAP")" '{"prompt":"   \n\t ","session_id":"s1"}' "$(seed_both s1 "$(state 1000 1000)" '{"":"empty-skill"}')" "$(read_state s1)"
add sid-session-id "$(env_at 1100)" '{"prompt":"hi","session_id":"abc-DEF_09"}' "$(seed_state abc-DEF_09 "$(state 1000 1000)")" "$(read_state abc-DEF_09)"
add sid-camel-case "$(env_at 1100)" '{"prompt":"hi","sessionId":"camel1"}' "$(seed_state camel1 "$(state 1000 1000)")" "$(read_state camel1)"
add sid-snake-beats-camel "$(env_at 1100)" '{"prompt":"hi","session_id":"snake1","sessionId":"camel1"}' "$(seed_state snake1 "$(state 1000 1000)")" "$(read_state snake1)"
add sid-empty-falls-to-camel "$(env_at 1100)" '{"prompt":"hi","session_id":"","sessionId":"camel1"}' "$(seed_state camel1 "$(state 1000 1000)")" "$(read_state camel1)"
add sid-missing-is-default "$(env_at 1100)" '{"prompt":"hi"}' "$(seed_state default "$(state 1000 1000)")" "$(read_state default)"
add sid-traversal-is-default "$(env_at 1100)" '{"prompt":"hi","session_id":"../../x"}' "$(seed_state default "$(state 1000 1000)")" "$(read_state default)"
add sid-dot-is-default "$(env_at 1100)" '{"prompt":"hi","session_id":"a.b"}' "$(seed_state default "$(state 1000 1000)")" "$(read_state default)"
add sid-space-is-default "$(env_at 1100)" '{"prompt":"hi","session_id":"a b"}' "$(seed_state default "$(state 1000 1000)")" "$(read_state default)"
add sid-64-chars "$(env_at 1100)" "$(jq -c -n --arg s "$(printf 'a%.0s' $(seq 64))" '{prompt:"hi",session_id:$s}')" "$(seed_state "$(printf 'a%.0s' $(seq 64))" "$(state 1000 1000)")" "$(read_state "$(printf 'a%.0s' $(seq 64))")"
add sid-65-chars-is-default "$(env_at 1100)" "$(jq -c -n --arg s "$(printf 'a%.0s' $(seq 65))" '{prompt:"hi",session_id:$s}')" "$(seed_state default "$(state 1000 1000)")" "$(read_state default)"
add sid-trailing-newline "$(env_at 1100)" '{"prompt":"hi","session_id":"nl1\n"}' '{}' '[]'
add sid-number "$(env_at 1100)" '{"prompt":"hi","session_id":123}' "$(seed_state 123 "$(state 1000 1000)")" "$(read_state 123)"
add sid-negative-number "$(env_at 1100)" '{"prompt":"hi","session_id":-5}' "$(seed_state -5 "$(state 1000 1000)")" "$(read_state -5)"
add sid-float-is-default "$(env_at 1100)" '{"prompt":"hi","session_id":1.5}' "$(seed_state default "$(state 1000 1000)")" "$(read_state default)"
add sid-true "$(env_at 1100)" '{"prompt":"hi","session_id":true}' "$(seed_state True "$(state 1000 1000)")" "$(read_state True)"
add sid-false-falls-through "$(env_at 1100)" '{"prompt":"hi","session_id":false,"sessionId":"camel1"}' "$(seed_state camel1 "$(state 1000 1000)")" "$(read_state camel1)"
add sid-list-is-default "$(env_at 1100)" '{"prompt":"hi","session_id":["a"]}' "$(seed_state default "$(state 1000 1000)")" "$(read_state default)"
add sid-object-is-default "$(env_at 1100)" '{"prompt":"hi","session_id":{"a":1}}' "$(seed_state default "$(state 1000 1000)")" "$(read_state default)"
add sid-unicode-is-default "$(env_at 1100)" '{"prompt":"hi","session_id":"phiên"}' "$(seed_state default "$(state 1000 1000)")" "$(read_state default)"

# --- the skill map ---
SK() { jq -c -n --arg m "$1" '{"home/st/s1.json": "{\"start\":1000,\"last\":1000}", "home/map.json": $m}'; }
PAY() { jq -c -n --arg p "$1" '{prompt:$p, session_id:"s1"}'; }
add map-hit "$(env_at 1100 "$MAP")" "$(PAY 'can you OCR this file')" "$(SK '{"ocr":"ocr-skill","deploy":"ship-skill"}')" "$(read_state s1)"
add map-two-hits-in-map-order "$(env_at 1100 "$MAP")" "$(PAY 'deploy then ocr')" "$(SK '{"ocr":"ocr-skill","deploy":"ship-skill"}')" "$(read_state s1)"
add map-reversed-key-order "$(env_at 1100 "$MAP")" "$(PAY 'alpha zeta')" "$(SK '{"zeta":"z-skill","alpha":"a-skill"}')" "$(read_state s1)"
add map-no-hit "$(env_at 1100 "$MAP")" "$(PAY 'nothing relevant')" "$(SK '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add map-word-boundary-no-hit "$(env_at 1100 "$MAP")" "$(PAY 'autocracy and socratic and democracy')" "$(SK '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add map-boundary-punctuation "$(env_at 1100 "$MAP")" "$(PAY 'run (ocr), then ocr.')" "$(SK '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add map-underscore-is-word "$(env_at 1100 "$MAP")" "$(PAY 'my_ocr_tool')" "$(SK '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add map-digit-is-word "$(env_at 1100 "$MAP")" "$(PAY 'ocr2 and 3ocr')" "$(SK '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add map-key-uppercase "$(env_at 1100 "$MAP")" "$(PAY 'please ocr')" "$(SK '{"OCR":"ocr-skill"}')" "$(read_state s1)"
add map-prompt-uppercase "$(env_at 1100 "$MAP")" "$(PAY 'PLEASE OCR')" "$(SK '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add map-regex-chars-escaped "$(env_at 1100 "$MAP")" "$(PAY 'open node.js and nodexjs')" "$(SK '{"node.js":"node-skill"}')" "$(read_state s1)"
add map-keyword-with-plus "$(env_at 1100 "$MAP")" "$(PAY 'write c++ code')" "$(SK '{"c++":"cpp-skill"}')" "$(read_state s1)"
add map-keyword-ends-nonword "$(env_at 1100 "$MAP")" "$(PAY 'use c++ now')" "$(SK '{"c++":"cpp-skill"}')" "$(read_state s1)"
add map-keyword-parens "$(env_at 1100 "$MAP")" "$(PAY 'call f(x) please')" "$(SK '{"f(x)":"fn-skill"}')" "$(read_state s1)"
add map-keyword-brackets-and-backslash "$(env_at 1100 "$MAP")" "$(PAY 'see [a] and a\\b ok')" "$(SK '{"[a]":"br-skill","a\\b":"bs-skill"}')" "$(read_state s1)"
add map-keyword-alternation-chars "$(env_at 1100 "$MAP")" "$(PAY 'a|b is not c')" "$(SK '{"a|b":"alt-skill","^c$":"anch-skill"}')" "$(read_state s1)"
add map-keyword-phrase "$(env_at 1100 "$MAP")" "$(PAY 'please code review this')" "$(SK '{"code review":"review-skill"}')" "$(read_state s1)"
add map-keyword-empty "$(env_at 1100 "$MAP")" "$(PAY 'hello')" "$(SK '{"":"empty-skill"}')" "$(read_state s1)"
add map-vietnamese "$(env_at 1100 "$MAP")" "$(PAY 'lên kế hoạch ĐÀ NẴNG tuần sau')" "$(SK '{"đà nẵng":"trip-skill"}')" "$(read_state s1)"
add map-accent-case "$(env_at 1100 "$MAP")" "$(PAY 'a CAFÉ visit')" "$(SK '{"café":"cafe-skill"}')" "$(read_state s1)"
add map-greek-case "$(env_at 1100 "$MAP")" "$(PAY 'ΑΘΗΝΑ trip')" "$(SK '{"αθηνα":"greek-skill"}')" "$(read_state s1)"
add map-cjk "$(env_at 1100 "$MAP")" "$(PAY '請用 测试 工具')" "$(SK '{"测试":"cjk-skill"}')" "$(read_state s1)"
add map-non-ascii-adjacent "$(env_at 1100 "$MAP")" "$(PAY 'dưocr và ocrđ')" "$(SK '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add map-value-number "$(env_at 1100 "$MAP")" "$(PAY 'ocr')" "$(SK '{"ocr":5}')" "$(read_state s1)"
add map-value-null "$(env_at 1100 "$MAP")" "$(PAY 'ocr')" "$(SK '{"ocr":null}')" "$(read_state s1)"
add map-value-true "$(env_at 1100 "$MAP")" "$(PAY 'ocr')" "$(SK '{"ocr":true}')" "$(read_state s1)"
add map-value-empty-string "$(env_at 1100 "$MAP")" "$(PAY 'ocr')" "$(SK '{"ocr":""}')" "$(read_state s1)"
add map-duplicate-key "$(env_at 1100 "$MAP")" "$(PAY 'ocr')" "$(SK '{"ocr":"first","ocr":"second"}')" "$(read_state s1)"
add map-empty-object "$(env_at 1100 "$MAP")" "$(PAY 'ocr')" "$(SK '{}')" "$(read_state s1)"
add map-invalid-json "$(env_at 1100 "$MAP")" "$(PAY 'ocr')" "$(SK 'not json')" "$(read_state s1)"
add map-empty-file "$(env_at 1100 "$MAP")" "$(PAY 'ocr')" "$(SK '')" "$(read_state s1)"
add crash-map-list "$(env_at 1100 "$MAP")" "$(PAY 'ocr')" "$(SK '["ocr"]')" "$(read_state s1)"
add crash-map-string "$(env_at 1100 "$MAP")" "$(PAY 'ocr')" "$(SK '"ocr"')" "$(read_state s1)"
add crash-map-null "$(env_at 1100 "$MAP")" "$(PAY 'ocr')" "$(SK 'null')" "$(read_state s1)"
add map-list-but-prompt-blank "$(env_at 1100 "$MAP")" "$(PAY ' ')" "$(SK '["ocr"]')" "$(read_state s1)"
add map-missing-file "$(env_at 1100 "$MAP")" "$(PAY 'ocr')" "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add map-path-empty '{"CONTEXT_HINTS_STATE":"@HOME@/st","CONTEXT_HINTS_NOW":"1100","CONTEXT_HINTS_SKILLMAP":""}' "$(PAY 'ocr')" "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add map-path-is-a-directory '{"CONTEXT_HINTS_STATE":"@HOME@/st","CONTEXT_HINTS_NOW":"1100","CONTEXT_HINTS_SKILLMAP":"@HOME@/mapdir"}' "$(PAY 'ocr')" '{"home/mapdir/x":"y"}' '[]'
add map-first-prompt-hint-only "$(env_at 1000 "$MAP")" "$(PAY 'ocr please')" "$(jq -c -n '{"home/map.json":"{\"ocr\":\"ocr-skill\"}"}')" "$(read_state s1)"
add map-default-shipped-empty "$(env_at 1100)" "$(PAY 'ocr please')" "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add map-long-prompt "$(env_at 1100 "$MAP")" "$(jq -c -n --arg p "$(printf 'filler %.0s' $(seq 2000))ocr" '{prompt:$p, session_id:"s1"}')" "$(SK '{"ocr":"ocr-skill"}')" "$(read_state s1)"
# --- found by the fresh review: surrogates, decomposed accents, BOMs, blank NOW, padded numbers ---
add payload-lone-high-surrogate "$(env_at 1100 "$MAP")" 'RAW:{"prompt":"half emoji \ud83d then ocr","session_id":"s1"}' "$(seed_both s1 "$(state 1000 1000)" '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add payload-lone-low-surrogate "$(env_at 1100 "$MAP")" 'RAW:{"prompt":"half emoji \ude00 then ocr","session_id":"s1"}' "$(seed_both s1 "$(state 1000 1000)" '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add payload-surrogate-pair "$(env_at 1100 "$MAP")" 'RAW:{"prompt":"emoji 😀 then ocr","session_id":"s1"}' "$(seed_both s1 "$(state 1000 1000)" '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add payload-escaped-backslash-u "$(env_at 1100 "$MAP")" 'RAW:{"prompt":"literal \\ud83d then ocr","session_id":"s1"}' "$(seed_both s1 "$(state 1000 1000)" '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add payload-bom "$(env_at 1100 "$MAP")" "RAW:$(printf '\xef\xbb\xbf')"'{"prompt":"ocr","session_id":"s1"}' "$(seed_both s1 "$(state 1000 1000)" '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add state-bom "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(printf '\xef\xbb\xbf')$(state 1000 1000)")" "$(read_state s1)"
add map-bom "$(env_at 1100 "$MAP")" "$(PAY 'ocr')" "$(SK "$(printf '\xef\xbb\xbf')"'{"ocr":"ocr-skill"}')" "$(read_state s1)"
add map-nfd-prompt-key-ca "$(env_at 1100 "$MAP")" "$(PAY "$(printf 'c\xc3\xa0 ph\xc3\xaa' | iconv -f UTF-8 -t UTF-8-MAC)")" "$(SK '{"ca":"coffee"}')" "$(read_state s1)"
add map-nfd-prompt-key-caf "$(env_at 1100 "$MAP")" "$(PAY "$(printf 'a caf\xc3\xa9 visit' | iconv -f UTF-8 -t UTF-8-MAC)")" "$(SK '{"caf":"cafe-skill"}')" "$(read_state s1)"
add map-nfd-key-vs-nfc-prompt "$(env_at 1100 "$MAP")" "$(PAY 'a café visit')" "$(SK "$(printf '{"cafe\xcc\x81":"cafe-skill"}')")" "$(read_state s1)"
add map-thai-vowel-boundary "$(env_at 1100 "$MAP")" "$(PAY 'ดี มาก')" "$(SK '{"ดี":"thai-skill"}')" "$(read_state s1)"
add map-overlapping-occurrences "$(env_at 1100 "$MAP")" "$(PAY 'aaaa aa')" "$(SK '{"aa":"aa-skill"}')" "$(read_state s1)"
add map-overlap-second-valid "$(env_at 1100 "$MAP")" "$(PAY 'x-a-a-a')" "$(SK '{"a-a":"dash-skill"}')" "$(read_state s1)"
add map-key-at-string-edges "$(env_at 1100 "$MAP")" "$(PAY 'ocr')" "$(SK '{"ocr":"ocr-skill"}')" "$(read_state s1)"
add now-whitespace-only-crash "$(env_at ' ')" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add now-whitespace-with-temporal-off "$(env_at ' ' '"CONTEXT_HINTS_TEMPORAL":"0"')" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 "$(state 1000 1000)")" "$(read_state s1)"
add state-padded-number-strings "$(env_at 1100)" '{"prompt":"hi","session_id":"s1"}' "$(seed_state s1 '{"start":" 1000 ","last":"1050\n"}')" "$(read_state s1)"
echo "wrote $(wc -l < "$OUT" | tr -d ' ') cases"
