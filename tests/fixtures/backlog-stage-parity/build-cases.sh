#!/usr/bin/env bash
# build-cases.sh -- writes cases.jsonl for the backlog-stage parity test. Each case is one JSON
# line the shared harness (tests/lib/hook-parity.sh) runs: name, env, payload, seed, read, args,
# touch, settle. The repo root is @CWD@, the state dir @HOME@/bs, and the model call is a stub
# extractor (@HOME@/ext.sh) that records the prompt it was sent and prints $EXT_JSON. A case
# named crash-* is one the Python crashed on: nothing is staged, as the Python shim left it.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/cases.jsonl"
: > "$OUT"

# add <name> <env-json> <payload-json|RAW:text> <seed-json> [read-json] [args-json] [touch-json] [settle-json]
add() {
  local name="$1" env="$2" payload="$3" seed="${4:-}" read="${5:-}" args="${6:-}" touch="${7:-}" settle="${8:-}"
  [ -n "$seed" ] || seed='{}'; [ -n "$read" ] || read='["cwd/_meta/backlog-staging.md","home/prompt.txt","home/prompt.txt.size"]'
  [ -n "$args" ] || args='[]'; [ -n "$touch" ] || touch='{}'; [ -n "$settle" ] || settle='[]'
  if [[ "$payload" == RAW:* ]]; then
    jq -c -n --arg n "$name" --argjson e "$env" --arg p "$payload" --argjson s "$seed" --argjson r "$read" --argjson a "$args" --argjson t "$touch" --argjson z "$settle" \
      '{name:$n, env:$e, payload:$p, seed:$s, read:$r, args:$a, touch:$t, settle:$z}' >> "$OUT"
  else
    jq -c -n --arg n "$name" --argjson e "$env" --argjson p "$payload" --argjson s "$seed" --argjson r "$read" --argjson a "$args" --argjson t "$touch" --argjson z "$settle" \
      '{name:$n, env:$e, payload:$p, seed:$s, read:$r, args:$a, touch:$t, settle:$z}' >> "$OUT"
  fi
}

BASE='"REPO_ROOT":"@CWD@","BACKLOG_STAGE_STATE_DIR":"@HOME@/bs","BACKLOG_STAGE_AUTO":"1","BACKLOG_STAGE_SYNC":"1","BACKLOG_STAGE_MIN_INTERVAL":"0","BACKLOG_STAGE_EXTRACTOR":"bash @HOME@/ext.sh","EXT_PROMPT_FILE":"@HOME@/prompt.txt"'
E() { printf '{%s%s}' "$BASE" "${1:+,$1}"; }
EXT='#!/bin/sh
cat > "$EXT_PROMPT_FILE"
wc -c < "$EXT_PROMPT_FILE" | tr -d " " > "$EXT_PROMPT_FILE.size"
if [ -f "$HOME/ext-out.txt" ]; then cat "$HOME/ext-out.txt"; else printf '"'"'%s'"'"' "$EXT_JSON"; fi
'
# S key text key text ...: a seed object
S() { local o; o=$(jq -c -n --arg k home/ext.sh --arg v "$EXT" '{($k): $v}'); while [ $# -ge 2 ]; do o=$(jq -c --arg k "$1" --arg v "$2" '.[$k] = $v' <<<"$o"); shift 2; done; printf '%s' "$o"; }
# TR <text>...: a transcript with alternating user and assistant text-block lines
TR() { local out="" i=0 who; for t in "$@"; do if [ $((i % 2)) = 0 ]; then who=user; else who=assistant; fi; out+=$(jq -c -n --arg w "$who" --arg t "$t" '{type:$w, message:{content:[{type:"text", text:$t}]}}')$'\n'; i=$((i + 1)); done; printf '%s' "$out"; }
P='{"transcript_path":"@CWD@/t.jsonl","session_id":"s1"}'
T1=$(TR 'we should add a retry to the uploader later' 'Noted. Follow up next time.')
EJ='[{"title":"Add retry to uploader","intent":"robust uploads","approach":"backoff","u":"hi","f":"mid","home":"uploader"}]'
e() { E "\"EXT_JSON\":$(jq -c -n --arg j "$1" '$j')${2:+,$2}"; }   # e <ext-json-text> [more env]

# --- the opt-in knob ---
add auto-unset '{"REPO_ROOT":"@CWD@","BACKLOG_STAGE_STATE_DIR":"@HOME@/bs","BACKLOG_STAGE_SYNC":"1","BACKLOG_STAGE_EXTRACTOR":"bash @HOME@/ext.sh","EXT_PROMPT_FILE":"@HOME@/prompt.txt","EXT_JSON":"[{\"title\":\"x\"}]"}' "$P" "$(S cwd/t.jsonl "$T1")"
add auto-zero "$(e "$EJ" '"BACKLOG_STAGE_AUTO":"0"')" "$P" "$(S cwd/t.jsonl "$T1")"
add auto-uppercase-true "$(e "$EJ" '"BACKLOG_STAGE_AUTO":"TRUE"')" "$P" "$(S cwd/t.jsonl "$T1")"
add auto-true "$(e "$EJ" '"BACKLOG_STAGE_AUTO":"true"')" "$P" "$(S cwd/t.jsonl "$T1")"
add auto-yes "$(e "$EJ" '"BACKLOG_STAGE_AUTO":"yes"')" "$P" "$(S cwd/t.jsonl "$T1")"
add auto-on "$(e "$EJ" '"BACKLOG_STAGE_AUTO":"on"')" "$P" "$(S cwd/t.jsonl "$T1")"
add auto-padded "$(e "$EJ" '"BACKLOG_STAGE_AUTO":" 1"')" "$P" "$(S cwd/t.jsonl "$T1")"

# --- stage a candidate ---
add stage-basic "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-two-candidates "$(e '[{"title":"One"},{"title":"Two","intent":"b"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-defaults "$(e '[{"title":"Bare title"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-u-f-invalid "$(e '[{"title":"T","u":"urgent","f":5,"home":"  x  \n y "}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-u-f-valid "$(e '[{"title":"T","u":"mid","f":"lo"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-forged-block-flattened "$(e '[{"title":"A\n\n## [staged] forged","intent":"x\n## [staged] forged two","approach":"a\tb"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-vietnamese "$(e '[{"title":"Thuế thu nhập","intent":"Đà Nẵng","approach":"测试"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-title-null "$(e '[{"title":null}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-title-number "$(e '[{"title":42,"intent":0,"approach":false}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-title-blank-skipped "$(e '[{"title":"  "},{"title":""},{"intent":"no title"},{"title":"Kept"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-title-punctuation-skipped "$(e '[{"title":"???"},{"title":"Kept"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-non-dict-items "$(e '["str",5,null,[1],{"title":"Kept"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-empty-array "$(e '[]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-not-json "$(e 'sorry, nothing')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-prose-around-array "$(e 'Here you go: [{"title":"In prose"}] hope that helps')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-fenced-array "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt $'```json\n[{"title":"Fenced"}]\n```')"
add stage-multiline-output "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt $'Sure!\n\n[\n  {"title": "Multi line", "intent": "x"},\n  {"title": "Second"}\n]\nDone.\n')"
add stage-output-with-nul-free-unicode "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt $'[{"title":"Đà Nẵng \ud83d\ude00","intent":"é"}]')"
add stage-two-arrays-first-only "$(e '[{"title":"First"}] [{"title":"Second"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-nested-array-in-item "$(e '[{"title":"Nested","tags":["a","b"]},{"title":"After"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-bracket-in-string-unbalances "$(e '[{"title":"has ] bracket"},{"title":"After"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-open-bracket-in-prose-first "$(e 'see [1] then [{"title":"X"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-unbalanced "$(e '[{"title":"cut off"}')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-object-not-array "$(e '{"title":"obj"}')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-array-invalid-json "$(e '[{"title": nope}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-extractor-prints-nothing "$(e '')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-extra-fields-ignored "$(e '[{"title":"T","note":"ignored","priority":1}]')" "$P" "$(S cwd/t.jsonl "$T1")"

# --- dedup against the board and the staging buffer ---
BOARD=$'| ID-1 | Add retry to uploader | n | queued |\n| ID-2 | Thuế thu nhập | | shipped |\n'
STG=$'# Backlog staging\n\n## [staged] Earlier proposal\n- Intent: x\n\n## [rejected] Old idea\n- Intent: y\n\n'
add dedup-board "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/BACKLOG.md "$BOARD")"
add dedup-board-case-and-punctuation "$(e '[{"title":"ADD  RETRY to uploader!"},{"title":"THUẾ THU NHẬP"}]')" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/BACKLOG.md "$BOARD")"
add dedup-staging "$(e '[{"title":"earlier proposal"},{"title":"OLD IDEA"},{"title":"fresh"}]')" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/backlog-staging.md "$STG")"
add dedup-within-batch "$(e '[{"title":"Same"},{"title":"same!"},{"title":"Other"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add dedup-staging-heading-without-title-not-borrowed "$(e '[{"title":"Intent x"},{"title":"Other"}]')" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/backlog-staging.md $'## [staged]\n- Intent: x\n\n')"
add dedup-staging-heading-spaces "$(e '[{"title":"A"}]')" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/backlog-staging.md $'## [staged]   \n\n')"
add dedup-staging-crlf "$(e '[{"title":"CRLF title"}]')" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/backlog-staging.md $'## [staged] CRLF title\r\n')"
add dedup-board-missing "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$T1")"
add dedup-staging-appended-not-rewritten "$(e '[{"title":"Newly staged"}]')" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/backlog-staging.md $'# Mine\n\n## [staged] Earlier\n- Intent: e\n\n')"
add backlog-env-override "$(e "$EJ" '"BACKLOG_STAGE_BACKLOG":"@CWD@/other.md"')" "$P" "$(S cwd/t.jsonl "$T1" cwd/other.md "$BOARD")"
add backlog-env-empty "$(e "$EJ" '"BACKLOG_STAGE_BACKLOG":""')" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/BACKLOG.md "$BOARD")"
add staging-env-override "$(e "$EJ" '"BACKLOG_STAGE_STAGING":"@CWD@/out/stage.md"')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/out/stage.md","home/prompt.txt","home/prompt.txt.size"]'
add crash-staging-relative "$(e "$EJ" '"BACKLOG_STAGE_STAGING":"stage.md"')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/stage.md","home/prompt.txt","home/prompt.txt.size"]'
add crash-staging-empty "$(e "$EJ" '"BACKLOG_STAGE_STAGING":""')" "$P" "$(S cwd/t.jsonl "$T1")" '["home/prompt.txt","home/prompt.txt.size"]'
add staging-dir-is-a-file "$(e "$EJ" '"BACKLOG_STAGE_STAGING":"@CWD@/notadir/stage.md"')" "$P" "$(S cwd/t.jsonl "$T1" cwd/notadir x)" '["home/prompt.txt","home/prompt.txt.size"]'
add staging-is-a-directory "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/backlog-staging.md/x y)" '["home/prompt.txt","home/prompt.txt.size"]'
add root-from-cwd-fallback "$(e "$EJ" | jq -c 'del(.REPO_ROOT)')" "$P" "$(S cwd/t.jsonl "$T1")"
add root-from-git "$(e "$EJ" | jq -c 'del(.REPO_ROOT)')" "$P" "$(S cwd/t.jsonl "$T1" cwd/.git/HEAD $'ref: refs/heads/main\n' cwd/.git/objects/.keep '' cwd/.git/refs/.keep '')"

# --- the payload ---
add payload-empty "$(e "$EJ")" 'RAW:' "$(S cwd/t.jsonl "$T1")"
add payload-not-json "$(e "$EJ")" 'RAW:not json' "$(S cwd/t.jsonl "$T1")"
add payload-list "$(e "$EJ")" 'RAW:[]' "$(S cwd/t.jsonl "$T1")"
add payload-two-objects "$(e "$EJ")" 'RAW:{"transcript_path":"@CWD@/t.jsonl"} {}' "$(S cwd/t.jsonl "$T1")"
add payload-no-transcript-path "$(e "$EJ")" '{"session_id":"s1"}' "$(S cwd/t.jsonl "$T1")"
add payload-transcript-path-empty "$(e "$EJ")" '{"transcript_path":""}' "$(S cwd/t.jsonl "$T1")"
add payload-transcript-path-missing-file "$(e "$EJ")" '{"transcript_path":"@CWD@/none.jsonl"}' "$(S cwd/t.jsonl "$T1")"
add payload-transcript-path-directory "$(e "$EJ")" '{"transcript_path":"@CWD@/d"}' "$(S cwd/d/x y)"
add payload-lone-high-surrogate "$(e "$EJ")" 'RAW:{"transcript_path":"@CWD@/t.jsonl","note":"half \ud83d emoji"}' "$(S cwd/t.jsonl "$T1")"
add payload-bom "$(e "$EJ")" "RAW:$(printf '\xef\xbb\xbf')"'{"transcript_path":"@CWD@/t.jsonl"}' "$(S cwd/t.jsonl "$T1")"
add payload-today-set "$(e "$EJ")" '{"transcript_path":"@CWD@/t.jsonl","_today":"2026-01-02"}' "$(S cwd/t.jsonl "$T1")"
add payload-today-number "$(e "$EJ")" '{"transcript_path":"@CWD@/t.jsonl","_today":20260102}' "$(S cwd/t.jsonl "$T1")"
add payload-today-falsy "$(e "$EJ")" '{"transcript_path":"@CWD@/t.jsonl","_today":""}' "$(S cwd/t.jsonl "$T1")"

# --- the transcript ---
add transcript-text-only-from-user-and-assistant "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"system","message":{"content":[{"type":"text","text":"we should ignore system"}]}}\n{"type":"user","message":{"content":[{"type":"text","text":"we should keep this"}]}}\n{"type":"assistant","message":{"content":[{"type":"tool_use","name":"x"},{"type":"text","text":"and this follow up"}]}}\n{"type":"summary","leaf":1}\n')"
add transcript-string-content-ignored "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":"we should have this plain string ignored"}}\n{"type":"user","message":{"content":[{"type":"text","text":"but we should keep this one"}]}}\n')"
add transcript-only-string-content "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":"we should do it later"}}\n')"
add transcript-blank-and-bad-lines "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'\nnot json\n   \n{"type":"user","message":{"content":[{"type":"text","text":"we should x"}]}} trailing\n{"type":"user","message":{"content":[{"type":"text","text":"we should y"}]}}\n')"
add transcript-crlf "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":[{"type":"text","text":"we should x"}]}}\r\n{"type":"assistant","message":{"content":[{"type":"text","text":"yes"}]}}\r\n')"
add transcript-text-empty-skipped "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":[{"type":"text","text":""},{"type":"text"},{"type":"text","text":"we should z"},{"type":"image","text":"no"}]}}\n')"
add transcript-message-null "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":null}\n{"type":"user","message":{"content":[{"type":"text","text":"we should x"}]}}\n')"
add transcript-content-null-and-empty "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":null}}\n{"type":"user","message":{"content":[]}}\n{"type":"user","message":{}}\n{"type":"user","message":{"content":[{"type":"text","text":"we should x"}]}}\n')"
add transcript-content-dict-ignored "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":{"type":"text","text":"we should dict"}}}\n{"type":"user","message":{"content":[{"type":"text","text":"we should x"}]}}\n')"
add transcript-content-list-of-non-dicts "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":["we should str",5,null,{"type":"text","text":"we should x"}]}}\n')"
add crash-transcript-line-not-object "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":[{"type":"text","text":"we should x"}]}}\n5\n')"
add crash-transcript-line-null "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'null\n{"type":"user","message":{"content":[{"type":"text","text":"we should x"}]}}\n')"
add crash-transcript-message-string "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":"we should x"}\n')"
add crash-transcript-message-list "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":["we should x"]}\n')"
add crash-transcript-content-number "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":7}}\n')"
add crash-transcript-text-number "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":[{"type":"text","text":5},{"type":"text","text":"we should x"}]}}\n')"
add transcript-other-type-bad-message-ignored "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"system","message":"a string"}\n{"type":"user","message":{"content":[{"type":"text","text":"we should x"}]}}\n')"
add transcript-empty-file "$(e "$EJ")" "$P" "$(S cwd/t.jsonl '')"
add transcript-no-text "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":[{"type":"tool_result","content":"we should"}]}}\n')"
add transcript-whitespace-only-text "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(TR '   ' $'\n\t')")"
add transcript-unicode "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(TR 'Mình cần làm: thuế, we should lên kế hoạch' '好的，next time 继续')")"
add transcript-text-is-prompt-verbatim "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(TR $'line one\nline two  spaced\n\n"quoted" \\ back' 'we should follow up')")"
add maxchars-small "$(e "$EJ" '"BACKLOG_STAGE_MAXCHARS":"20"')" "$P" "$(S cwd/t.jsonl "$(TR 'we should add a retry to the uploader later' 'Noted. Follow up next time.')")"
add maxchars-exact-length "$(e "$EJ" '"BACKLOG_STAGE_MAXCHARS":"22"')" "$P" "$(S cwd/t.jsonl "$(TR 'we should do it' 'ok')")"
add maxchars-zero-keeps-all "$(e "$EJ" '"BACKLOG_STAGE_MAXCHARS":"0"')" "$P" "$(S cwd/t.jsonl "$T1")"
add maxchars-negative-drops-head "$(e "$EJ" '"BACKLOG_STAGE_MAXCHARS":"-10"')" "$P" "$(S cwd/t.jsonl "$T1")"
add maxchars-negative-beyond-length "$(e "$EJ" '"BACKLOG_STAGE_MAXCHARS":"-9999"')" "$P" "$(S cwd/t.jsonl "$T1")"
add maxchars-padded "$(e "$EJ" '"BACKLOG_STAGE_MAXCHARS":" 30 "')" "$P" "$(S cwd/t.jsonl "$T1")"
add maxchars-unicode-slice "$(e "$EJ" '"BACKLOG_STAGE_MAXCHARS":"6"')" "$P" "$(S cwd/t.jsonl "$(TR 'we should lên kế hoạch ĐÀ NẴNG' 'ok')")"
add crash-maxchars-invalid "$(e "$EJ" '"BACKLOG_STAGE_MAXCHARS":"abc"')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/backlog-staging.md","home/prompt.txt","home/prompt.txt.size","home/bs/last-run"]'
add crash-maxchars-float "$(e "$EJ" '"BACKLOG_STAGE_MAXCHARS":"12.5"')" "$P" "$(S cwd/t.jsonl "$T1")"

# --- the forward-intent pre-filter ---
pi=0
for phrase in 'a todo item' 'a to-do item' 'add to the backlog' 'we should' 'I should' 'should we' "let's go" 'lets go' 'next time' 'follow up' 'follow-up' 'followup' 'remind me' 'a reminder' 'need to' 'have to' 'going to' 'gonna' 'plan to' 'want to' 'in the future' 'revisit this' 'circle back' 'action item' 'down the line' 'later on' 'come back to it' 'for later'; do
  pi=$((pi + 1)); slug=$(printf '%s' "$phrase" | tr -c 'a-zA-Z0-9\n' '-' | tr 'A-Z' 'a-z')
  add "prefilter-hit-$pi-$slug" "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(TR "xx $phrase yy")")"
done
add prefilter-upper-case "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(TR 'WE SHOULD DO IT' 'TODO later')")"
add prefilter-miss "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(TR 'hello there' 'general kenobi')")"
add prefilter-word-boundary-miss "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(TR 'todos and reminders and gonnas' 'shoulders')")"
add prefilter-bare-should-and-later-miss "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(TR 'it should work' 'see you later')")"
add prefilter-off "$(e "$EJ" '"BACKLOG_STAGE_PREFILTER":"0"')" "$P" "$(S cwd/t.jsonl "$(TR 'hello there' 'general kenobi')")"
add prefilter-env-other-value-is-on "$(e "$EJ" '"BACKLOG_STAGE_PREFILTER":"off"')" "$P" "$(S cwd/t.jsonl "$(TR 'hello there' 'general kenobi')")"
add prefilter-vietnamese-miss "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(TR 'cần làm sau' 'lần sau')")"

# --- the extractor ---
add extractor-nonzero-exit-keeps-stdout "$(e "$EJ" '"BACKLOG_STAGE_EXTRACTOR":"bash @HOME@/ext-fail.sh"')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-fail.sh $'#!/bin/sh\ncat > "$EXT_PROMPT_FILE"\nprintf \'%s\' "$EXT_JSON"\nexit 3\n')"
add extractor-missing-binary "$(e "$EJ" '"BACKLOG_STAGE_EXTRACTOR":"no-such-binary-xyz --flag"')" "$P" "$(S cwd/t.jsonl "$T1")"
add extractor-quoted-args "$(e "$EJ" '"BACKLOG_STAGE_EXTRACTOR":"bash @HOME@/ext-args.sh \"two words\" '"'"'single q'"'"'"')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-args.sh $'#!/bin/sh\ncat > "$EXT_PROMPT_FILE"\nprintf \'[{"title":"%s | %s"}]\' "$1" "$2"\n')"
add crash-extractor-unbalanced-quote "$(e "$EJ" '"BACKLOG_STAGE_EXTRACTOR":"bash \"unterminated"')" "$P" "$(S cwd/t.jsonl "$T1")"
add extractor-reads-prompt-head "$(e '[]')" "$P" "$(S cwd/t.jsonl "$T1")"

# --- the throttle ---
add throttle-first-run-creates-stamp "$(e "$EJ" '"BACKLOG_STAGE_MIN_INTERVAL":"3600"')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/backlog-staging.md","home/bs/last-run"]'
add throttle-fresh-stamp "$(e "$EJ" '"BACKLOG_STAGE_MIN_INTERVAL":"3600"')" "$P" "$(S cwd/t.jsonl "$T1" home/bs/last-run '')" '["cwd/_meta/backlog-staging.md","home/prompt.txt","home/prompt.txt.size"]'
add throttle-old-stamp "$(e "$EJ" '"BACKLOG_STAGE_MIN_INTERVAL":"3600"')" "$P" "$(S cwd/t.jsonl "$T1" home/bs/last-run '')" '["cwd/_meta/backlog-staging.md"]' '[]' '{"home/bs/last-run":1500000000}'
add throttle-default-interval-fresh "$(e "$EJ" | jq -c 'del(.BACKLOG_STAGE_MIN_INTERVAL)')" "$P" "$(S cwd/t.jsonl "$T1" home/bs/last-run '')" '["cwd/_meta/backlog-staging.md","home/prompt.txt","home/prompt.txt.size"]'
add throttle-interval-zero "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$T1" home/bs/last-run '')"
add throttle-interval-negative "$(e "$EJ" '"BACKLOG_STAGE_MIN_INTERVAL":"-5"')" "$P" "$(S cwd/t.jsonl "$T1" home/bs/last-run '')"
add throttle-interval-invalid "$(e "$EJ" '"BACKLOG_STAGE_MIN_INTERVAL":"abc"')" "$P" "$(S cwd/t.jsonl "$T1" home/bs/last-run '')" '["cwd/_meta/backlog-staging.md","home/prompt.txt","home/prompt.txt.size"]'
add throttle-interval-float "$(e "$EJ" '"BACKLOG_STAGE_MIN_INTERVAL":"3.5"')" "$P" "$(S cwd/t.jsonl "$T1" home/bs/last-run '')" '["cwd/_meta/backlog-staging.md","home/prompt.txt","home/prompt.txt.size"]'
add throttle-before-transcript-read "$(e "$EJ" '"BACKLOG_STAGE_MIN_INTERVAL":"3600"')" '{"transcript_path":"@CWD@/none.jsonl"}' '{}' '["home/bs/last-run"]'
add throttle-state-dir-is-a-file "$(e "$EJ" '"BACKLOG_STAGE_MIN_INTERVAL":"3600","BACKLOG_STAGE_STATE_DIR":"@HOME@/f/bs"')" "$P" "$(S cwd/t.jsonl "$T1" home/f x)"
add throttle-no-transcript-leaves-no-stamp "$(e "$EJ" '"BACKLOG_STAGE_MIN_INTERVAL":"3600"')" '{"session_id":"s"}' '{}' '["home/bs/last-run"]'
add state-dir-default "$(e "$EJ" '"BACKLOG_STAGE_MIN_INTERVAL":"3600"' | jq -c 'del(.BACKLOG_STAGE_STATE_DIR)')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/backlog-staging.md","home/.claude/dwarves-kit/state/backlog-stage/last-run"]'
add state-dir-empty "$(e "$EJ" '"BACKLOG_STAGE_MIN_INTERVAL":"3600","BACKLOG_STAGE_STATE_DIR":""')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/backlog-staging.md","cwd/last-run"]'

# --- sync knob and the detached child ---
add sync-true-padded-upper "$(e "$EJ" '"BACKLOG_STAGE_SYNC":" TRUE "')" "$P" "$(S cwd/t.jsonl "$T1")"
add sync-yes "$(e "$EJ" '"BACKLOG_STAGE_SYNC":"yes"')" "$P" "$(S cwd/t.jsonl "$T1")"
add detached-basic "$(e "$EJ" '"BACKLOG_STAGE_SYNC":"0"')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/backlog-staging.md","home/prompt.txt","home/prompt.txt.size"]' '[]' '{}' '["home/bs/payload-*.json"]'
add detached-sync-unset "$(e "$EJ" | jq -c 'del(.BACKLOG_STAGE_SYNC)')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/backlog-staging.md","home/prompt.txt","home/prompt.txt.size"]' '[]' '{}' '["home/bs/payload-*.json"]'
add detached-no-candidates "$(e '[]' '"BACKLOG_STAGE_SYNC":"0"')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/backlog-staging.md","home/prompt.txt","home/prompt.txt.size"]' '[]' '{}' '["home/bs/payload-*.json"]'
add detached-dedup-against-board "$(e "$EJ" '"BACKLOG_STAGE_SYNC":"0"')" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/BACKLOG.md "$BOARD")" '["cwd/_meta/backlog-staging.md","home/prompt.txt","home/prompt.txt.size"]' '[]' '{}' '["home/bs/payload-*.json"]'
add detached-prefilter-miss "$(e "$EJ" '"BACKLOG_STAGE_SYNC":"0"')" "$P" "$(S cwd/t.jsonl "$(TR 'hello' 'there')")" '["cwd/_meta/backlog-staging.md","home/prompt.txt","home/prompt.txt.size"]' '[]' '{}' '["home/bs/payload-*.json"]'
add detached-state-dir-unwritable "$(e "$EJ" '"BACKLOG_STAGE_SYNC":"0","BACKLOG_STAGE_STATE_DIR":"@HOME@/f/bs"')" "$P" "$(S cwd/t.jsonl "$T1" home/f x)"
add detached-today-payload "$(e "$EJ" '"BACKLOG_STAGE_SYNC":"0"')" '{"transcript_path":"@CWD@/t.jsonl","_today":"2026-03-04"}' "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/backlog-staging.md"]' '[]' '{}' '["home/bs/payload-*.json"]'

# --- --staged-run, the child entry point ---
PF='{"text":"we should add a retry","date":"2026-05-06","backlog":"@CWD@/_meta/BACKLOG.md","staging":"@CWD@/_meta/backlog-staging.md"}'
add staged-run-basic "$(e "$EJ")" 'RAW:' "$(S home/pf.json "$PF")" '["cwd/_meta/backlog-staging.md","home/prompt.txt","home/prompt.txt.size","home/pf.json"]' '["--staged-run","@HOME@/pf.json"]'
add staged-run-without-auto "$(e "$EJ" '"BACKLOG_STAGE_AUTO":""')" 'RAW:' "$(S home/pf.json "$PF")" '["cwd/_meta/backlog-staging.md","home/pf.json"]' '["--staged-run","@HOME@/pf.json"]'
add staged-run-missing-file "$(e "$EJ")" 'RAW:' '{}' '["cwd/_meta/backlog-staging.md"]' '["--staged-run","@HOME@/none.json"]'
add staged-run-no-argument "$(e "$EJ")" 'RAW:' '{}' '["cwd/_meta/backlog-staging.md"]' '["--staged-run"]'
add staged-run-corrupt-json "$(e "$EJ")" 'RAW:' "$(S home/pf.json 'not json')" '["cwd/_meta/backlog-staging.md","home/pf.json"]' '["--staged-run","@HOME@/pf.json"]'
add staged-run-missing-key "$(e "$EJ")" 'RAW:' "$(S home/pf.json '{"text":"x","date":"d"}')" '["cwd/_meta/backlog-staging.md","home/pf.json"]' '["--staged-run","@HOME@/pf.json"]'
add staged-run-dedups "$(e "$EJ")" 'RAW:' "$(S home/pf.json "$PF" cwd/_meta/BACKLOG.md "$BOARD")" '["cwd/_meta/backlog-staging.md","home/pf.json"]' '["--staged-run","@HOME@/pf.json"]'

# --- --surface, the SessionStart count line ---
SURF='"BACKLOG_STAGE_STAGING":"@CWD@/_meta/backlog-staging.md"'
add surface-no-staging-file "$(E)" 'RAW:' '{}' '[]' '["--surface"]'
add surface-zero-staged "$(E)" 'RAW:' "$(S cwd/_meta/backlog-staging.md $'# Backlog staging\n\n## [rejected] x\n## [promoted ID-1] y\n')" '[]' '["--surface"]'
add surface-one-staged "$(E)" 'RAW:' "$(S cwd/_meta/backlog-staging.md $'## [staged] One\n')" '[]' '["--surface"]'
add surface-three-staged "$(E)" 'RAW:' "$(S cwd/_meta/backlog-staging.md $'## [staged] A\n- x\n## [staged] B\n## [rejected] C\n## [staged] D\n')" '[]' '["--surface"]'
add surface-crlf "$(E)" 'RAW:' "$(S cwd/_meta/backlog-staging.md $'## [staged] A\r\n## [staged] B\r\n')" '[]' '["--surface"]'
add surface-heading-needs-exact-prefix "$(E)" 'RAW:' "$(S cwd/_meta/backlog-staging.md $' ## [staged] indented\n##[staged] no space\n## [staged]x\n## [staged] ok\n')" '[]' '["--surface"]'
add surface-env-staging "$(E '"BACKLOG_STAGE_STAGING":"@CWD@/out/s.md"')" 'RAW:' "$(S cwd/out/s.md $'## [staged] A\n')" '[]' '["--surface"]'
add surface-without-auto "$(E '"BACKLOG_STAGE_AUTO":""')" 'RAW:' "$(S cwd/_meta/backlog-staging.md $'## [staged] A\n')" '[]' '["--surface"]'
add surface-staging-is-directory "$(E)" 'RAW:' "$(S cwd/_meta/backlog-staging.md/x y)" '[]' '["--surface"]'
add surface-runs-intake-sweep-first "$(E '"INTAKE_SWEEP_STATE_DIR":"@HOME@/is"')" 'RAW:' "$(S cwd/_meta/intake-sources.json '{"sources":[{"name":"l","kind":"jsonl","path":"data/l.jsonl"}]}' cwd/data/l.jsonl $'{"title":"Swept item","url":"https://ex.com/s"}\n')" '["cwd/_meta/backlog-staging.md","home/is/swept-keys.txt"]' '["--surface"]'
add surface-sweep-config-absent "$(E)" 'RAW:' "$(S cwd/_meta/backlog-staging.md $'## [staged] A\n')" '[]' '["--surface","--other"]'
add surface-flag-anywhere "$(E)" 'RAW:' "$(S cwd/_meta/backlog-staging.md $'## [staged] A\n')" '[]' '["--x","--surface"]'

# --- classes the intake-sweep review found, applied here ---
add transcript-bom-first-line-skipped "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(printf '\xef\xbb\xbf')"$'{"type":"user","message":{"content":[{"type":"text","text":"we should first"}]}}\n{"type":"user","message":{"content":[{"type":"text","text":"we should second"}]}}\n')"
add model-output-bom-is-fine "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt "$(printf '\xef\xbb\xbf[{"title":"After BOM"}]')")"
add dedup-board-cr-line-breaks "$(e '[{"title":"Add retry to uploader"},{"title":"Fresh one"}]')" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/BACKLOG.md $'| ID-1 | Add retry to uploader | n |\r| ID-2 | Other | n |\r')"
add dedup-board-vt-is-not-a-line-break "$(e '[{"title":"Add retry to uploader"},{"title":"Second row"}]')" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/BACKLOG.md $'| ID-1 | Add retry to uploader | n |\x0b| ID-2 | Second row | n |\x0c')"
add dedup-staging-cr-line-breaks "$(e '[{"title":"Earlier"},{"title":"Fresh one"}]')" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/backlog-staging.md $'## [staged] Earlier\r- Intent: x\r## [rejected] Old\r')"
add root-trailing-slash "$(e "$EJ" | jq -c '.REPO_ROOT = "@CWD@/"')" "$P" "$(S cwd/t.jsonl "$T1")"
add throttle-interval-huge "$(e "$EJ" '"BACKLOG_STAGE_MIN_INTERVAL":"99999999999999999999999"')" "$P" "$(S cwd/t.jsonl "$T1" home/bs/last-run '')" '["cwd/_meta/backlog-staging.md","home/prompt.txt"]'
add surface-cr-only-lines "$(E)" 'RAW:' "$(S cwd/_meta/backlog-staging.md $'## [staged] A\r## [staged] B\r## [rejected] C\r')" '[]' '["--surface"]'
add staged-run-text-not-string "$(e "$EJ")" 'RAW:' "$(S home/pf.json '{"text":5,"date":"d","backlog":"@CWD@/b.md","staging":"@CWD@/s.md"}')" '["cwd/s.md","home/pf.json"]' '["--staged-run","@HOME@/pf.json"]'
add staged-run-date-number "$(e "$EJ")" 'RAW:' "$(S home/pf.json '{"text":"we should x","date":20260102,"backlog":"@CWD@/b.md","staging":"@CWD@/s.md"}')" '["cwd/s.md","home/pf.json"]' '["--staged-run","@HOME@/pf.json"]'

# --- found by the fresh review of this port ---
add crash-transcript-invalid-utf8 "$(e "$EJ")" "$P" "$(S cwd/t.jsonl 'base64:eyJ0eXBlIjoidXNlciIsIm1lc3NhZ2UiOnsiY29udGVudCI6W3sidHlwZSI6InRleHQiLCJ0ZXh0Ijoid2Ugc2hvdWxkIHgifV19fQp7InR5cGUiOiJ1c2VyIiwibWVzc2FnZSI6eyJjb250ZW50IjpbeyJ0eXBlIjoidGV4dCIsInRleHQiOiJiYWQg/yBieXRlIn1dfX0K')"
add crash-model-output-invalid-utf8 "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt 'base64:W3sidGl0bGUiOiJiYWQg/yBieXRlIn1d')"
add surface-staging-not-utf8 "$(E)" 'RAW:' "$(S cwd/_meta/backlog-staging.md 'base64:IyMgW3N0YWdlZF0gRWFybGllciD/IHRpdGxlCg==')" '[]' '["--surface"]'
add crash-staging-not-utf8-after-model-call "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/backlog-staging.md 'base64:IyMgW3N0YWdlZF0gRWFybGllciD/IHRpdGxlCg==')"
add soh-in-transcript-text-sync "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(TR $'we should a\x01b and \x01\x01 c' 'ok')")"
add soh-in-transcript-text-detached "$(e "$EJ" '"BACKLOG_STAGE_SYNC":"0"')" "$P" "$(S cwd/t.jsonl "$(TR $'we should a\x01b and \x01\x01 c' 'ok')")" '["cwd/_meta/backlog-staging.md","home/prompt.txt","home/prompt.txt.size"]' '[]' '{}' '["home/bs/payload-*.json"]'
add soh-in-staged-run-payload "$(e "$EJ")" 'RAW:' "$(S home/pf.json '{"text":"we should a\u0001b \u0001\u0001 c","date":"d","backlog":"@CWD@/b.md","staging":"@CWD@/s.md"}')" '["cwd/s.md","home/prompt.txt","home/prompt.txt.size","home/pf.json"]' '["--staged-run","@HOME@/pf.json"]'
add payload-transcript-path-number-passes-throttle-then-crashes "$(e "$EJ" '"BACKLOG_STAGE_MIN_INTERVAL":"3600"')" '{"transcript_path":5}' '{}' '["cwd/_meta/backlog-staging.md","home/bs/last-run"]'
add payload-transcript-path-true-passes-throttle-then-crashes "$(e "$EJ" '"BACKLOG_STAGE_MIN_INTERVAL":"3600"')" '{"transcript_path":true}' '{}' '["home/bs/last-run"]'
add staged-run-flag-not-first "$(e "$EJ")" 'RAW:' "$(S cwd/t.jsonl "$T1" home/pf.json "$PF")" '["cwd/_meta/backlog-staging.md","home/pf.json"]' '["--other","--staged-run","@HOME@/pf.json"]'
add staged-run-date-null "$(e "$EJ")" 'RAW:' "$(S home/pf.json '{"text":"we should x","date":null,"backlog":"@CWD@/b.md","staging":"@CWD@/s.md"}')" '["cwd/s.md","home/pf.json"]' '["--staged-run","@HOME@/pf.json"]'
add staged-run-date-true "$(e "$EJ")" 'RAW:' "$(S home/pf.json '{"text":"we should x","date":true,"backlog":"@CWD@/b.md","staging":"@CWD@/s.md"}')" '["cwd/s.md","home/pf.json"]' '["--staged-run","@HOME@/pf.json"]'
add staged-run-payload-bom "$(e "$EJ")" 'RAW:' "$(S home/pf.json 'base64:77u/eyJ0ZXh0Ijoid2Ugc2hvdWxkIHgiLCJkYXRlIjoiZCIsImJhY2tsb2ciOiIiLCJzdGFnaW5nIjoiIn0=')" '["cwd/s.md","home/pf.json"]' '["--staged-run","@HOME@/pf.json"]'
add staged-run-payload-invalid-utf8 "$(e "$EJ")" 'RAW:' "$(S home/pf.json 'base64:eyJ0ZXh0Ijoid2Ugc2hvdWxkIP8iLCJkYXRlIjoiZCIsImJhY2tsb2ciOiJAQ1dEQC9iLm1kIiwic3RhZ2luZyI6IkBDV0RAL3MubWQifQ==')" '["cwd/s.md","home/pf.json","home/prompt.txt"]' '["--staged-run","@HOME@/pf.json"]'
add crash-extractor-blank-command "$(e "$EJ" '"BACKLOG_STAGE_EXTRACTOR":"   "')" "$P" "$(S cwd/t.jsonl "$T1")"
add dedup-board-unit-separator-lead "$(e '[{"title":"Add retry to uploader"},{"title":"Fresh one"}]')" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/BACKLOG.md "$(printf '\x1f| ID-1 | Add retry to uploader | n |\n')")"
add extractor-timeout-discards-stdout "$(e "$EJ" '"BACKLOG_STAGE_EXTRACTOR":"bash @HOME@/ext-hang.sh","PATH":"@HOME@/shim:@PATH@"')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-hang.sh $'#!/bin/sh\ncat > "$EXT_PROMPT_FILE"\nprintf \'%s\' "$EXT_JSON"\n/bin/sleep 130\n' home/shim/sleep $'#!/bin/sh\nexec /bin/sleep 1\n')"
echo "wrote $(wc -l < "$OUT" | tr -d ' ') cases"
