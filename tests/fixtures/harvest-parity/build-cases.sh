#!/usr/bin/env bash
# build-cases.sh -- writes cases.jsonl for the harvest parity test. Each case is one JSON line the
# shared harness (tests/lib/hook-parity.sh) runs: name, env, payload, seed, read, args, touch, settle.
# The repo root is @CWD@, the state dir @HOME@/hv, and the model call is a stub extractor
# (@HOME@/ext.sh) that records the prompt it was sent (and its byte count) and prints $EXT_JSON or
# the file home/ext-out.txt. A case named crash-* is one the Python crashed on: nothing is staged,
# as the Python shim left it.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/cases.jsonl"
: > "$OUT"

# add <name> <env-json> <payload-json|RAW:text> <seed-json> [read-json] [args-json] [touch-json] [settle-json]
add() {
  local name="$1" env="$2" payload="$3" seed="${4:-}" read="${5:-}" args="${6:-}" touch="${7:-}" settle="${8:-}"
  [ -n "$seed" ] || seed='{}'; [ -n "$read" ] || read='["cwd/_meta/learned-ledger.md","home/prompt.txt","home/prompt.txt.size"]'
  [ -n "$args" ] || args='[]'; [ -n "$touch" ] || touch='{}'; [ -n "$settle" ] || settle='[]'
  if [[ "$payload" == RAW:* ]]; then
    jq -c -n --arg n "$name" --argjson e "$env" --arg p "$payload" --argjson s "$seed" --argjson r "$read" --argjson a "$args" --argjson t "$touch" --argjson z "$settle" \
      '{name:$n, env:$e, payload:$p, seed:$s, read:$r, args:$a, touch:$t, settle:$z}' >> "$OUT"
  else
    jq -c -n --arg n "$name" --argjson e "$env" --argjson p "$payload" --argjson s "$seed" --argjson r "$read" --argjson a "$args" --argjson t "$touch" --argjson z "$settle" \
      '{name:$n, env:$e, payload:$p, seed:$s, read:$r, args:$a, touch:$t, settle:$z}' >> "$OUT"
  fi
}

BASE='"REPO_ROOT":"@CWD@","HARVEST_STATE_DIR":"@HOME@/hv","HARVEST_SYNC":"1","HARVEST_MIN_INTERVAL":"0","HARVEST_EXTRACTOR":"bash @HOME@/ext.sh","EXT_PROMPT_FILE":"@HOME@/prompt.txt"'
E() { printf '{%s%s}' "$BASE" "${1:+,$1}"; }
EXT='#!/bin/sh
cat > "$EXT_PROMPT_FILE"
wc -c < "$EXT_PROMPT_FILE" | tr -d " " > "$EXT_PROMPT_FILE.size"
if [ -f "$HOME/ext-out.txt" ]; then cat "$HOME/ext-out.txt"; else printf '"'"'%s'"'"' "$EXT_JSON"; fi
'
S() { local o; o=$(jq -c -n --arg k home/ext.sh --arg v "$EXT" '{($k): $v}'); while [ $# -ge 2 ]; do o=$(jq -c --arg k "$1" --arg v "$2" '.[$k] = $v' <<<"$o"); shift 2; done; printf '%s' "$o"; }
TR() { local out="" i=0 who; for t in "$@"; do if [ $((i % 2)) = 0 ]; then who=user; else who=assistant; fi; out+=$(jq -c -n --arg w "$who" --arg t "$t" '{type:$w, message:{content:[{type:"text", text:$t}]}}')$'\n'; i=$((i + 1)); done; printf '%s' "$out"; }
P='{"transcript_path":"@CWD@/t.jsonl","session_id":"s1"}'
T1=$(TR 'We decided to keep the ledger append-only.' 'Noted: dedup happens under a lock.')
EJ='[{"item":"Ledger Is Append Only","kind":"decision","home":"til","why":"keep history"},{"item":"dedup under a lock","kind":"insight","home":"research","why":"races"}]'
e() { E "\"EXT_JSON\":$(jq -c -n --arg j "$1" '$j')${2:+,$2}"; }
LEDGER='cwd/_meta/learned-ledger.md'
ROWS=$'| date | item | kind | home | status |\n|---|---|---|---|---|\n| 2026-01-01 | known-item | insight | til | queued |\n| 2026-01-02 | flushed-item | decision | drop | flushed:ID-9 |\n'

# --- the default harvest (no flag) ---
add stage-basic "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/learned-ledger.md","cwd/_meta/learned-ledger.md.lock","home/prompt.txt","home/prompt.txt.size"]'
add stage-kind-home-normalized "$(e '[{"item":"a","kind":"bogus","home":"bogus"},{"item":"b","kind":"concept","home":"glossary"},{"item":"c","kind":"insight","home":"drop"},{"item":"d","kind":"decision","home":"til"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-kind-home-wrong-case-and-types "$(e '[{"item":"a","kind":"Insight","home":"TIL"},{"item":"b","kind":5,"home":null}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-slug-rules "$(e '[{"item":"Hello, World! 2026"},{"item":"snake_case_item"},{"item":"  --Leading and trailing--  "},{"item":"Đà Nẵng trip"},{"item":"测试 item"},{"item":"UPPER lower Mixed"},{"item":"a...b///c"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-slug-truncated-60 "$(e "$(jq -c -n --arg a "$(printf 'word%.0s ' $(seq 30))" '[{item:$a}]')")" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-slug-truncated-ends-hyphen "$(e "$(jq -c -n --arg a "$(printf 'a%.0s' $(seq 59)) bcd" '[{item:$a}]')")" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-item-empty-or-punctuation "$(e '[{"item":""},{"item":"!!!"},{"item":"   "},{"kind":"insight"},{"item":"kept"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-item-non-string "$(e '[{"item":42},{"item":true},{"item":null},{"item":1.5},{"item":"ok"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-non-dict-candidates "$(e '["str",5,null,[1],{"item":"kept"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-empty-array "$(e '[]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-not-json "$(e 'nothing to keep')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-prose-around-array "$(e 'Here: [{"item":"in prose","kind":"insight","home":"til"}] ok')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-fenced-array "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt $'```json\n[{"item":"fenced"}]\n```')"
add stage-two-arrays-first-only "$(e '[{"item":"first"}] [{"item":"second"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-bracket-in-string-unbalances "$(e '[{"item":"has ] bracket"},{"item":"after"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-unbalanced "$(e '[{"item":"cut off"}')" "$P" "$(S cwd/t.jsonl "$T1")"
add stage-extra-fields-ignored "$(e '[{"item":"x","why":"w","evidence":"e","extra":1}]')" "$P" "$(S cwd/t.jsonl "$T1")"

# --- dedup: the ledger, glossaries, the batch, fuzzy ---
add dedup-ledger-any-status "$(e '[{"item":"Known Item"},{"item":"flushed item"},{"item":"fresh"}]')" "$P" "$(S cwd/t.jsonl "$T1" $LEDGER "$ROWS")"
add dedup-ledger-malformed-rows "$(e '[{"item":"odd row"},{"item":"short row"},{"item":"badly dated"},{"item":"fresh"}]')" "$P" "$(S cwd/t.jsonl "$T1" $LEDGER $'| date | item | kind | home | status |\n|---|---|---|---|---|\n| 2026-01-01 | odd row | x |\n| 2026-1-1 | badly dated | a | b | queued |\n| nope | short row | a | b | queued |\n|2026-01-03|tight|a|b|queued|\n')"
add dedup-ledger-appended-not-rewritten "$(e '[{"item":"new one"}]')" "$P" "$(S cwd/t.jsonl "$T1" $LEDGER "$ROWS")"
add dedup-glossary-headings "$(e '[{"item":"Alpha Concept"},{"item":"beta sub"},{"item":"gamma deep"},{"item":"delta top"},{"item":"epsilon body"},{"item":"fresh"}]')" "$P" "$(S cwd/t.jsonl "$T1" cwd/learning/x/GLOSSARY.md $'# delta top\n## Alpha Concept\nepsilon body is prose here\n### beta sub\n#### gamma deep\n##### five hashes\n##nospace\n')"
add dedup-glossary-two-tracks "$(e '[{"item":"one"},{"item":"two"},{"item":"three"}]')" "$P" "$(S cwd/t.jsonl "$T1" cwd/learning/a/GLOSSARY.md $'## one\n' cwd/learning/b/GLOSSARY.md $'## two\n')"
add dedup-glossaries-env "$(e '[{"item":"one"},{"item":"two"},{"item":"three"}]' '"HARVEST_GLOSSARIES":"@CWD@/g1.md:@CWD@/missing.md::@CWD@/g2.md"')" "$P" "$(S cwd/t.jsonl "$T1" cwd/g1.md $'## one\n' cwd/g2.md $'## two\n' cwd/learning/a/GLOSSARY.md $'## three\n')"
add dedup-glossaries-env-empty-uses-default "$(e '[{"item":"three"},{"item":"four"}]' '"HARVEST_GLOSSARIES":""')" "$P" "$(S cwd/t.jsonl "$T1" cwd/learning/a/GLOSSARY.md $'## three\n')"
add dedup-within-batch "$(e '[{"item":"Same"},{"item":"same!"},{"item":"other"}]')" "$P" "$(S cwd/t.jsonl "$T1")"
add dedup-all-known-writes-nothing "$(e '[{"item":"known item"}]')" "$P" "$(S cwd/t.jsonl "$T1" $LEDGER "$ROWS")" '["cwd/_meta/learned-ledger.md","cwd/_meta/learned-ledger.md.lock","home/prompt.txt","home/prompt.txt.size"]'
add fuzzy-off-by-default "$(e '[{"item":"known-itemx"},{"item":"known-item-two"}]')" "$P" "$(S cwd/t.jsonl "$T1" $LEDGER "$ROWS")"
add fuzzy-one "$(e '[{"item":"known-itemx"},{"item":"known-ite"},{"item":"totally different"}]' '"HARVEST_FUZZY_THRESHOLD":"1"')" "$P" "$(S cwd/t.jsonl "$T1" $LEDGER "$ROWS")"
add fuzzy-two-batch "$(e '[{"item":"abcdefgh"},{"item":"abcdefxx"},{"item":"abcdexxx"}]' '"HARVEST_FUZZY_THRESHOLD":"2"')" "$P" "$(S cwd/t.jsonl "$T1")"
add fuzzy-invalid-is-off "$(e '[{"item":"known-itemx"}]' '"HARVEST_FUZZY_THRESHOLD":"abc"')" "$P" "$(S cwd/t.jsonl "$T1" $LEDGER "$ROWS")"
add fuzzy-negative-is-off "$(e '[{"item":"known-itemx"}]' '"HARVEST_FUZZY_THRESHOLD":"-3"')" "$P" "$(S cwd/t.jsonl "$T1" $LEDGER "$ROWS")"
add fuzzy-unicode-slugs "$(e '[{"item":"cafe"},{"item":"cafes"}]' '"HARVEST_FUZZY_THRESHOLD":"1"')" "$P" "$(S cwd/t.jsonl "$T1")"

# --- where the files live ---
add ledger-env-override "$(e "$EJ" '"HARVEST_LEDGER":"@CWD@/out/ledger.md"')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/out/ledger.md","cwd/out/ledger.md.lock","home/prompt.txt"]'
add ledger-env-empty-uses-default "$(e "$EJ" '"HARVEST_LEDGER":""')" "$P" "$(S cwd/t.jsonl "$T1")"
add crash-ledger-relative "$(e "$EJ" '"HARVEST_LEDGER":"ledger.md"')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/ledger.md","cwd/ledger.md.lock","home/prompt.txt"]'
add ledger-dir-is-a-file "$(e "$EJ" '"HARVEST_LEDGER":"@CWD@/notadir/ledger.md"')" "$P" "$(S cwd/t.jsonl "$T1" cwd/notadir x)" '["home/prompt.txt"]'
add ledger-is-a-directory "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$T1" cwd/_meta/learned-ledger.md/x y)" '["home/prompt.txt"]'
add root-from-cwd-fallback "$(e "$EJ" | jq -c 'del(.REPO_ROOT)')" "$P" "$(S cwd/t.jsonl "$T1")"
add root-from-git "$(e "$EJ" | jq -c 'del(.REPO_ROOT)')" "$P" "$(S cwd/t.jsonl "$T1" cwd/.git/HEAD $'ref: refs/heads/main\n' cwd/.git/objects/.keep '' cwd/.git/refs/.keep '')"

# --- the payload and the transcript (same walk as backlog-stage, no pre-filter) ---
add payload-empty "$(e "$EJ")" 'RAW:' "$(S cwd/t.jsonl "$T1")"
add payload-not-json "$(e "$EJ")" 'RAW:not json' "$(S cwd/t.jsonl "$T1")"
add payload-list "$(e "$EJ")" 'RAW:[]' "$(S cwd/t.jsonl "$T1")"
add payload-no-transcript-path "$(e "$EJ")" '{"session_id":"s1"}' "$(S cwd/t.jsonl "$T1")"
add payload-transcript-path-missing-file "$(e "$EJ")" '{"transcript_path":"@CWD@/none.jsonl"}' "$(S cwd/t.jsonl "$T1")"
add payload-lone-high-surrogate "$(e "$EJ")" 'RAW:{"transcript_path":"@CWD@/t.jsonl","note":"half \ud83d emoji"}' "$(S cwd/t.jsonl "$T1")"
add payload-bom "$(e "$EJ")" "RAW:$(printf '\xef\xbb\xbf')"'{"transcript_path":"@CWD@/t.jsonl"}' "$(S cwd/t.jsonl "$T1")"
add transcript-no-intent-still-extracts "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(TR 'hello there' 'general kenobi')")"
add transcript-only-user-and-assistant "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"system","message":{"content":[{"type":"text","text":"ignore system"}]}}\n{"type":"user","message":{"content":[{"type":"text","text":"keep user"}]}}\n{"type":"assistant","message":{"content":[{"type":"tool_use","name":"x"},{"type":"text","text":"keep assistant"}]}}\n')"
add transcript-string-content-ignored "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":"plain string ignored"}}\n{"type":"user","message":{"content":[{"type":"text","text":"kept"}]}}\n')"
add transcript-only-string-content "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":"plain string"}}\n')"
add transcript-blank-and-bad-lines "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'\nnot json\n   \n{"type":"user","message":{"content":[{"type":"text","text":"x"}]}} trailing\n{"type":"user","message":{"content":[{"type":"text","text":"y"}]}}\n')"
add transcript-crlf "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":[{"type":"text","text":"x"}]}}\r\n{"type":"assistant","message":{"content":[{"type":"text","text":"yes"}]}}\r\n')"
add transcript-message-null-and-empty-content "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":null}\n{"type":"user","message":{"content":null}}\n{"type":"user","message":{"content":[]}}\n{"type":"user","message":{"content":{"type":"text","text":"dict ignored"}}}\n{"type":"user","message":{"content":[{"type":"text","text":"kept"}]}}\n')"
add transcript-unicode "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(TR 'Mình cần làm: thuế, lên kế hoạch' '好的，继续')")"
add transcript-text-is-prompt-verbatim "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(TR $'line one\nline two  spaced\n\n"quoted" \\ back' 'done')")"
add transcript-whitespace-only-text "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(TR '   ' $'\n\t')")"
add transcript-empty-file "$(e "$EJ")" "$P" "$(S cwd/t.jsonl '')"
add crash-transcript-line-not-object "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":[{"type":"text","text":"x"}]}}\n5\n')"
add crash-transcript-message-string "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":"x"}\n')"
add crash-transcript-content-number "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":7}}\n')"
add crash-transcript-text-number "$(e "$EJ")" "$P" "$(S cwd/t.jsonl $'{"type":"user","message":{"content":[{"type":"text","text":5},{"type":"text","text":"x"}]}}\n')"
add maxchars-small "$(e "$EJ" '"HARVEST_MAXCHARS":"20"')" "$P" "$(S cwd/t.jsonl "$T1")"
add maxchars-zero-keeps-all "$(e "$EJ" '"HARVEST_MAXCHARS":"0"')" "$P" "$(S cwd/t.jsonl "$T1")"
add maxchars-negative-drops-head "$(e "$EJ" '"HARVEST_MAXCHARS":"-10"')" "$P" "$(S cwd/t.jsonl "$T1")"
add maxchars-padded "$(e "$EJ" '"HARVEST_MAXCHARS":" 30 "')" "$P" "$(S cwd/t.jsonl "$T1")"
add maxchars-unicode-slice "$(e "$EJ" '"HARVEST_MAXCHARS":"9"')" "$P" "$(S cwd/t.jsonl "$(TR 'lên kế hoạch ĐÀ NẴNG' 'ok')")"
add crash-maxchars-invalid "$(e "$EJ" '"HARVEST_MAXCHARS":"abc"')" "$P" "$(S cwd/t.jsonl "$T1")"

# --- the extractor ---
add extractor-nonzero-exit-keeps-stdout "$(e "$EJ" '"HARVEST_EXTRACTOR":"bash @HOME@/ext-fail.sh"')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-fail.sh $'#!/bin/sh\ncat > "$EXT_PROMPT_FILE"\nprintf \'%s\' "$EXT_JSON"\nexit 3\n')"
add extractor-missing-binary "$(e "$EJ" '"HARVEST_EXTRACTOR":"no-such-binary-xyz --flag"')" "$P" "$(S cwd/t.jsonl "$T1")"
add extractor-quoted-args "$(e "$EJ" '"HARVEST_EXTRACTOR":"bash @HOME@/ext-args.sh \"two words\" '"'"'single q'"'"'"')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-args.sh $'#!/bin/sh\ncat > "$EXT_PROMPT_FILE"\nprintf \'[{"item":"%s %s"}]\' "$1" "$2"\n')"
add crash-extractor-unbalanced-quote "$(e "$EJ" '"HARVEST_EXTRACTOR":"bash \"unterminated"')" "$P" "$(S cwd/t.jsonl "$T1")"

# --- the debounce ---
add debounce-first-run-writes-stamp "$(e "$EJ" '"HARVEST_MIN_INTERVAL":"3600"')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/learned-ledger.md","home/hv/last-ledger"]'
add debounce-fresh-stamp "$(e "$EJ" '"HARVEST_MIN_INTERVAL":"3600"')" "$P" "$(S cwd/t.jsonl "$T1" home/hv/last-ledger 1)" '["cwd/_meta/learned-ledger.md","home/prompt.txt","home/hv/last-ledger"]'
add debounce-old-stamp "$(e "$EJ" '"HARVEST_MIN_INTERVAL":"3600"')" "$P" "$(S cwd/t.jsonl "$T1" home/hv/last-ledger 1)" '["cwd/_meta/learned-ledger.md","home/hv/last-ledger"]' '[]' '{"home/hv/last-ledger":1500000000}'
add debounce-default-interval-fresh "$(e "$EJ" | jq -c 'del(.HARVEST_MIN_INTERVAL)')" "$P" "$(S cwd/t.jsonl "$T1" home/hv/last-ledger 1)"
add debounce-interval-zero-no-stamp "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$T1" home/hv/last-ledger 1)" '["cwd/_meta/learned-ledger.md","home/hv/last-ledger"]'
add debounce-interval-invalid "$(e "$EJ" '"HARVEST_MIN_INTERVAL":"abc"')" "$P" "$(S cwd/t.jsonl "$T1" home/hv/last-ledger 1)" '["cwd/_meta/learned-ledger.md","home/prompt.txt"]'
add debounce-interval-negative "$(e "$EJ" '"HARVEST_MIN_INTERVAL":"-5"')" "$P" "$(S cwd/t.jsonl "$T1" home/hv/last-ledger 1)"
add debounce-before-payload-read "$(e "$EJ" '"HARVEST_MIN_INTERVAL":"3600"')" 'RAW:' '{}' '["home/hv/last-ledger"]'
add debounce-state-dir-is-a-file "$(e "$EJ" '"HARVEST_MIN_INTERVAL":"3600","HARVEST_STATE_DIR":"@HOME@/f/hv"')" "$P" "$(S cwd/t.jsonl "$T1" home/f x)"
add state-dir-default "$(e "$EJ" '"HARVEST_MIN_INTERVAL":"3600"' | jq -c 'del(.HARVEST_STATE_DIR)')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/learned-ledger.md","home/.claude/dwarves-kit/state/harvest/last-ledger"]'

# --- sync knob and the detached child ---
add sync-padded-upper "$(e "$EJ" '"HARVEST_SYNC":" TRUE "')" "$P" "$(S cwd/t.jsonl "$T1")"
add detached-basic "$(e "$EJ" '"HARVEST_SYNC":"0"')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/learned-ledger.md","home/prompt.txt","home/prompt.txt.size"]' '[]' '{}' '["home/hv/payload-*.json"]'
add detached-sync-unset "$(e "$EJ" | jq -c 'del(.HARVEST_SYNC)')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/learned-ledger.md","home/prompt.txt"]' '[]' '{}' '["home/hv/payload-*.json"]'
add detached-no-candidates "$(e '[]' '"HARVEST_SYNC":"0"')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/learned-ledger.md","home/prompt.txt"]' '[]' '{}' '["home/hv/payload-*.json"]'
add detached-state-dir-unwritable "$(e "$EJ" '"HARVEST_SYNC":"0","HARVEST_STATE_DIR":"@HOME@/f/hv"')" "$P" "$(S cwd/t.jsonl "$T1" home/f x)"

# --- --lab-log ---
LL=$'## 2026-10-16 - session-slug: did the thing\n- one\n- two\n- three'
add lablog-basic "$(e '' '"HARVEST_LABLOG_DRAFT":"@CWD@/_meta/.lab-log-draft.md"')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt "$LL")" '["cwd/_meta/.lab-log-draft.md","home/prompt.txt","home/prompt.txt.size"]' '["--lab-log"]'
add lablog-default-draft-path "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt "$LL")" '["cwd/_meta/.lab-log-draft.md"]' '["--lab-log"]'
add lablog-none "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt 'NONE')" '["cwd/_meta/.lab-log-draft.md","home/prompt.txt"]' '["--lab-log"]'
add lablog-none-lowercase "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt 'none, nothing worth logging')" '["cwd/_meta/.lab-log-draft.md"]' '["--lab-log"]'
add lablog-empty-output "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt '')" '["cwd/_meta/.lab-log-draft.md"]' '["--lab-log"]'
add lablog-fenced "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt $'```markdown\n## 2026-10-16 - slug: x\n- a\n```')" '["cwd/_meta/.lab-log-draft.md"]' '["--lab-log"]'
add lablog-not-a-heading "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt $'# Title\n- just bullets\n## not dated')" '["cwd/_meta/.lab-log-draft.md"]' '["--lab-log"]'
add lablog-heading-not-first-line "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt $'Here is the entry:\n## 2026-10-16 - slug: x\n- a')" '["cwd/_meta/.lab-log-draft.md"]' '["--lab-log"]'
add lablog-trailing-whitespace "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt $'\n\n## 2026-10-16 - slug: x  \n- a   \n\n\n')" '["cwd/_meta/.lab-log-draft.md"]' '["--lab-log"]'
add lablog-appends-to-existing "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt "$LL" cwd/_meta/.lab-log-draft.md $'earlier draft\n\n')" '["cwd/_meta/.lab-log-draft.md"]' '["--lab-log"]'
add lablog-unicode "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt $'## 2026-10-16 - đà-nẵng: xong\n- 测试')" '["cwd/_meta/.lab-log-draft.md"]' '["--lab-log"]'
add lablog-draft-env-override "$(e '' '"HARVEST_LABLOG_DRAFT":"@CWD@/out/draft.md"')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt "$LL")" '["cwd/out/draft.md"]' '["--lab-log"]'
add lablog-draft-env-empty-uses-default "$(e '' '"HARVEST_LABLOG_DRAFT":""')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt "$LL")" '["cwd/_meta/.lab-log-draft.md"]' '["--lab-log"]'
add crash-lablog-draft-relative "$(e '' '"HARVEST_LABLOG_DRAFT":"draft.md"')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt "$LL")" '["cwd/draft.md"]' '["--lab-log"]'
add lablog-no-transcript "$(e '')" '{"session_id":"s"}' "$(S cwd/t.jsonl "$T1" home/ext-out.txt "$LL")" '["cwd/_meta/.lab-log-draft.md","home/hv/last-lablog"]' '["--lab-log"]'
add lablog-debounce-writes-own-stamp "$(e '' '"HARVEST_MIN_INTERVAL":"3600"')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt "$LL")" '["cwd/_meta/.lab-log-draft.md","home/hv/last-lablog","home/hv/last-ledger"]' '["--lab-log"]'
add lablog-debounce-fresh "$(e '' '"HARVEST_MIN_INTERVAL":"3600"')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt "$LL" home/hv/last-lablog 1)" '["cwd/_meta/.lab-log-draft.md","home/prompt.txt"]' '["--lab-log"]'
add lablog-debounce-ledger-stamp-independent "$(e '' '"HARVEST_MIN_INTERVAL":"3600"')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt "$LL" home/hv/last-ledger 1)" '["cwd/_meta/.lab-log-draft.md"]' '["--lab-log"]'
add lablog-detached "$(e '' '"HARVEST_SYNC":"0"')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt "$LL")" '["cwd/_meta/.lab-log-draft.md","home/prompt.txt"]' '["--lab-log"]' '{}' '["home/hv/payload-*.json"]'
add lablog-prompt-has-today "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt 'NONE')" '["home/prompt.txt","home/prompt.txt.size"]' '["--lab-log"]'
add crash-lablog-maxchars-invalid "$(e '' '"HARVEST_MAXCHARS":"abc"')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt "$LL")" '["cwd/_meta/.lab-log-draft.md"]' '["--lab-log"]'

# --- --stop-trigger ---
STOP='"HARVEST_STOP_TRIGGER":"1"'
add stop-off-by-default "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/learned-ledger.md","home/hv/turns/s1"]' '["--stop-trigger"]'
add stop-first-turn-skips "$(e "$EJ" "$STOP")" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/learned-ledger.md","home/hv/turns/s1"]' '["--stop-trigger"]'
add stop-tenth-turn-fires "$(e "$EJ" "$STOP")" "$P" "$(S cwd/t.jsonl "$T1" home/hv/turns/s1 9)" '["cwd/_meta/learned-ledger.md","home/hv/turns/s1","home/hv/harvest.lock"]' '["--stop-trigger"]' '{}' '["home/hv/payload-*.json"]'
add stop-n-two-fires-on-second "$(e "$EJ" "$STOP"',"HARVEST_STOP_N":"2","HARVEST_STOP_SYNC":"1"')" "$P" "$(S cwd/t.jsonl "$T1" home/hv/turns/s1 1)" '["cwd/_meta/learned-ledger.md","home/hv/turns/s1"]' '["--stop-trigger"]'
add stop-n-two-skips-on-first "$(e "$EJ" "$STOP"',"HARVEST_STOP_N":"2","HARVEST_STOP_SYNC":"1"')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/learned-ledger.md","home/hv/turns/s1"]' '["--stop-trigger"]'
add stop-n-invalid-is-ten "$(e "$EJ" "$STOP"',"HARVEST_STOP_N":"abc","HARVEST_STOP_SYNC":"1"')" "$P" "$(S cwd/t.jsonl "$T1" home/hv/turns/s1 9)" '["cwd/_meta/learned-ledger.md","home/hv/turns/s1"]' '["--stop-trigger"]'
add stop-n-zero-is-one "$(e "$EJ" "$STOP"',"HARVEST_STOP_N":"0","HARVEST_STOP_SYNC":"1"')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/learned-ledger.md","home/hv/turns/s1"]' '["--stop-trigger"]'
add stop-n-negative-is-one "$(e "$EJ" "$STOP"',"HARVEST_STOP_N":"-4","HARVEST_STOP_SYNC":"1"')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/learned-ledger.md","home/hv/turns/s1"]' '["--stop-trigger"]'
add stop-sync-fire "$(e "$EJ" "$STOP"',"HARVEST_STOP_SYNC":"1"')" "$P" "$(S cwd/t.jsonl "$T1" home/hv/turns/s1 9)" '["cwd/_meta/learned-ledger.md","home/hv/turns/s1","home/hv/harvest.lock","home/prompt.txt"]' '["--stop-trigger"]'
add stop-detached-fire "$(e "$EJ" "$STOP")" "$P" "$(S cwd/t.jsonl "$T1" home/hv/turns/s1 9)" '["cwd/_meta/learned-ledger.md","home/hv/turns/s1","home/prompt.txt"]' '["--stop-trigger"]' '{}' '["home/hv/payload-*.json"]'
add stop-counter-corrupt-resets "$(e "$EJ" "$STOP")" "$P" "$(S cwd/t.jsonl "$T1" home/hv/turns/s1 garbage)" '["home/hv/turns/s1"]' '["--stop-trigger"]'
add stop-counter-empty-file "$(e "$EJ" "$STOP")" "$P" "$(S cwd/t.jsonl "$T1" home/hv/turns/s1 '')" '["home/hv/turns/s1"]' '["--stop-trigger"]'
add stop-counter-padded "$(e "$EJ" "$STOP")" "$P" "$(S cwd/t.jsonl "$T1" home/hv/turns/s1 ' 4
')" '["home/hv/turns/s1"]' '["--stop-trigger"]'
add stop-session-id-sanitized "$(e "$EJ" "$STOP")" '{"transcript_path":"@CWD@/t.jsonl","session_id":"a/b c..d"}' "$(S cwd/t.jsonl "$T1")" '["home/hv/turns/a_b_c..d"]' '["--stop-trigger"]'
add stop-session-id-missing "$(e "$EJ" "$STOP")" '{"transcript_path":"@CWD@/t.jsonl"}' "$(S cwd/t.jsonl "$T1")" '["home/hv/turns/nosession"]' '["--stop-trigger"]'
add stop-session-id-empty "$(e "$EJ" "$STOP")" '{"transcript_path":"@CWD@/t.jsonl","session_id":""}' "$(S cwd/t.jsonl "$T1")" '["home/hv/turns/nosession"]' '["--stop-trigger"]'
add stop-session-id-number "$(e "$EJ" "$STOP")" '{"transcript_path":"@CWD@/t.jsonl","session_id":123}' "$(S cwd/t.jsonl "$T1")" '["home/hv/turns/123"]' '["--stop-trigger"]'
add stop-session-id-long "$(e "$EJ" "$STOP")" "$(jq -c -n --arg s "$(printf 'z%.0s' $(seq 200))" '{transcript_path:"@CWD@/t.jsonl", session_id:$s}')" "$(S cwd/t.jsonl "$T1")" "$(jq -c -n --arg s "$(printf 'z%.0s' $(seq 128))" '["home/hv/turns/" + $s]')" '["--stop-trigger"]'
add stop-no-transcript-still-counts "$(e "$EJ" "$STOP"',"HARVEST_STOP_SYNC":"1"')" '{"session_id":"s1"}' "$(S cwd/t.jsonl "$T1" home/hv/turns/s1 9)" '["cwd/_meta/learned-ledger.md","home/hv/turns/s1"]' '["--stop-trigger"]'
add stop-payload-empty "$(e "$EJ" "$STOP")" 'RAW:' '{}' '["home/hv/turns/nosession"]' '["--stop-trigger"]'
add stop-payload-not-json "$(e "$EJ" "$STOP")" 'RAW:not json' '{}' '["home/hv/turns/nosession"]' '["--stop-trigger"]'
add stop-state-dir-is-a-file "$(e "$EJ" "$STOP"',"HARVEST_STATE_DIR":"@HOME@/f/hv"')" "$P" "$(S cwd/t.jsonl "$T1" home/f x)" '["cwd/_meta/learned-ledger.md"]' '["--stop-trigger"]'
add stop-trigger-env-yes "$(e "$EJ" '"HARVEST_STOP_TRIGGER":"yes"')" "$P" "$(S cwd/t.jsonl "$T1")" '["home/hv/turns/s1"]' '["--stop-trigger"]'
add stop-trigger-env-zero-is-off "$(e "$EJ" '"HARVEST_STOP_TRIGGER":"0"')" "$P" "$(S cwd/t.jsonl "$T1")" '["home/hv/turns/s1"]' '["--stop-trigger"]'

# --- the detached children, driven directly ---
PFH='{"transcript_path":"@CWD@/t.jsonl","session_id":"s1"}'
add harvest-run-basic "$(e "$EJ")" 'RAW:' "$(S cwd/t.jsonl "$T1" home/pf.json "$PFH")" '["cwd/_meta/learned-ledger.md","home/prompt.txt","home/pf.json","home/hv/harvest.lock"]' '["--harvest-run","@HOME@/pf.json"]'
add harvest-run-missing-file "$(e "$EJ")" 'RAW:' "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/learned-ledger.md"]' '["--harvest-run","@HOME@/none.json"]'
add harvest-run-no-argument "$(e "$EJ")" 'RAW:' "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/learned-ledger.md"]' '["--harvest-run"]'
add harvest-run-corrupt-json "$(e "$EJ")" 'RAW:' "$(S cwd/t.jsonl "$T1" home/pf.json 'not json')" '["cwd/_meta/learned-ledger.md","home/pf.json"]' '["--harvest-run","@HOME@/pf.json"]'
add harvest-run-payload-list "$(e "$EJ")" 'RAW:' "$(S cwd/t.jsonl "$T1" home/pf.json '[1]')" '["cwd/_meta/learned-ledger.md","home/pf.json"]' '["--harvest-run","@HOME@/pf.json"]'
add harvest-run-no-transcript-path "$(e "$EJ")" 'RAW:' "$(S cwd/t.jsonl "$T1" home/pf.json '{"session_id":"s"}')" '["cwd/_meta/learned-ledger.md","home/pf.json"]' '["--harvest-run","@HOME@/pf.json"]'
add lab-log-run-basic "$(e '')" 'RAW:' "$(S cwd/t.jsonl "$T1" home/pf.json "$PFH" home/ext-out.txt "$LL")" '["cwd/_meta/.lab-log-draft.md","home/pf.json"]' '["--lab-log-run","@HOME@/pf.json"]'
add lab-log-run-corrupt "$(e '')" 'RAW:' "$(S cwd/t.jsonl "$T1" home/pf.json 'x' home/ext-out.txt "$LL")" '["cwd/_meta/.lab-log-draft.md","home/pf.json"]' '["--lab-log-run","@HOME@/pf.json"]'
add stop-harvest-basic "$(e "$EJ")" 'RAW:' "$(S cwd/t.jsonl "$T1" home/pf.json "$PFH")" '["cwd/_meta/learned-ledger.md","home/pf.json","home/hv/harvest.lock"]' '["--stop-harvest","@HOME@/pf.json"]'
add stop-harvest-missing-file "$(e "$EJ")" 'RAW:' "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/learned-ledger.md"]' '["--stop-harvest","@HOME@/none.json"]'

# --- the sweep gate in the shim (already bash) ---
add sweep-child-marker-exits "$(e "$EJ" '"HARVEST_SWEEP_CHILD":"1"')" "$P" "$(S cwd/t.jsonl "$T1")" '["cwd/_meta/learned-ledger.md","home/prompt.txt"]'
add sweep-child-marker-explicit-verb-not-gated "$(e '[]' '"HARVEST_SWEEP_CHILD":"1"')" 'RAW:' '{}' '["home/hv/sweep/ledger"]' '["--cleanup","@CWD@/none.md"]'

# --- the operator verbs, which run in the sweep module ---
SL='home/hv/sweep/ledger/proj.md'
SR=$'| date | item | kind | home | status |\n|---|---|---|---|---|\n| 2026-01-01 | one | insight | til | queued |\n| 2026-01-02 | two | decision | drop | flushed:ID-1 |\n| 2026-01-03 | three | concept | glossary | queued |\n'
ROWS_NOFLUSH=$'| date | item | kind | home | status |\n|---|---|---|---|---|\n| 2026-01-01 | one | insight | til | queued |\n'
add cleanup-archives-flushed "$(e '[]')" 'RAW:' "$(S cwd/t.jsonl "$T1" $LEDGER "$SR")" '["cwd/_meta/learned-ledger.md","cwd/_meta/learned-ledger.archive.md","cwd/_meta/learned-ledger.md.lock"]' '["--cleanup"]'
add cleanup-no-flushed-rows "$(e '[]')" 'RAW:' "$(S cwd/t.jsonl "$T1" $LEDGER "$ROWS_NOFLUSH")" '["cwd/_meta/learned-ledger.md","cwd/_meta/learned-ledger.archive.md","cwd/_meta/learned-ledger.md.lock"]' '["--cleanup"]'
add cleanup-no-ledger "$(e '[]')" 'RAW:' '{}' '["cwd/_meta/learned-ledger.md"]' '["--cleanup"]'
add cleanup-explicit-ledger "$(e '[]')" 'RAW:' "$(S cwd/other.md "$SR")" '["cwd/other.md","cwd/other.archive.md"]' '["--cleanup","@CWD@/other.md"]'
add cleanup-appends-to-archive "$(e '[]')" 'RAW:' "$(S $LEDGER "$SR" cwd/_meta/learned-ledger.archive.md $'| date | item | kind | home | status |\n|---|---|---|---|---|\n| 2025-12-01 | old | insight | til | flushed:ID-0 |\n')" '["cwd/_meta/learned-ledger.md","cwd/_meta/learned-ledger.archive.md"]' '["--cleanup"]'
add flush-list-empty "$(e '[]')" 'RAW:' '{}' '[]' '["--flush-list"]'
add flush-list-rows "$(e '[]')" 'RAW:' "$(S $SL "$SR" home/hv/sweep/ledger/proj.rows.jsonl $'{"row_id":"proj:one","why":"w","evidence":"e","source":"claude/abc","lead_session_id":"L1"}\nnot json\n{"no_row_id":1}\n')" '[]' '["--flush-list"]'
add flush-list-two-ledgers-and-archive "$(e '[]')" 'RAW:' "$(S $SL "$SR" home/hv/sweep/ledger/other.md "$SR" home/hv/sweep/ledger/other.archive.md "$SR")" '[]' '["--flush-list"]'
add mark-flushed-flips-queued-row "$(e '[]')" 'RAW:' "$(S $SL "$SR")" "[\"$SL\"]" '["--mark-flushed","proj:one","ID-77"]'
add mark-flushed-already-flushed "$(e '[]')" 'RAW:' "$(S $SL "$SR")" "[\"$SL\"]" '["--mark-flushed","proj:two","ID-78"]'
add mark-flushed-unknown-row "$(e '[]')" 'RAW:' "$(S $SL "$SR")" "[\"$SL\"]" '["--mark-flushed","proj:nope","ID-79"]'
add mark-flushed-unknown-ledger "$(e '[]')" 'RAW:' "$(S $SL "$SR")" "[\"$SL\"]" '["--mark-flushed","zzz:one","ID-80"]'
add mark-flushed-missing-args "$(e '[]')" 'RAW:' "$(S $SL "$SR")" "[\"$SL\"]" '["--mark-flushed","proj:one"]'
add mark-flushed-ref-sanitized "$(e '[]')" 'RAW:' "$(S $SL "$SR")" "[\"$SL\"]" '["--mark-flushed","proj:one","I|D 1"]'
add status-routes-to-sweep "$(e '[]')" 'RAW:' '{}' '[]' '["--status"]'

# --- the classes the earlier reviews found, applied here ---
add crash-transcript-invalid-utf8 "$(e "$EJ")" "$P" "$(S cwd/t.jsonl 'base64:eyJ0eXBlIjoidXNlciIsIm1lc3NhZ2UiOnsiY29udGVudCI6W3sidHlwZSI6InRleHQiLCJ0ZXh0Ijoid2UgZGVjaWRlZCB4In1dfX0KeyJ0eXBlIjoidXNlciIsIm1lc3NhZ2UiOnsiY29udGVudCI6W3sidHlwZSI6InRleHQiLCJ0ZXh0IjoiYmFkIP8gYnl0ZSJ9XX19Cg==')"
add crash-model-output-invalid-utf8 "$(e '')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-out.txt 'base64:W3siaXRlbSI6ImJhZCD/IGJ5dGUifV0=')"
add crash-ledger-invalid-utf8 "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$T1" $LEDGER 'base64:fCBkYXRlIHwgaXRlbSB8IGtpbmQgfCBob21lIHwgc3RhdHVzIHwKfC0tLXwtLS18LS0tfC0tLXwtLS18CnwgMjAyNi0wMS0wMSB8IGNhZukgfCBpbnNpZ2h0IHwgdGlsIHwgcXVldWVkIHwK')"
add transcript-bom-first-line-skipped "$(e "$EJ")" "$P" "$(S cwd/t.jsonl "$(printf '\xef\xbb\xbf')"$'{"type":"user","message":{"content":[{"type":"text","text":"first"}]}}\n{"type":"user","message":{"content":[{"type":"text","text":"second"}]}}\n')"
add soh-in-transcript-text-detached "$(e "$EJ" '"HARVEST_SYNC":"0"')" "$P" "$(S cwd/t.jsonl "$(TR $'we decided a\x01b and \x01\x01 c' 'ok')")" '["cwd/_meta/learned-ledger.md","home/prompt.txt","home/prompt.txt.size"]' '[]' '{}' '["home/hv/payload-*.json"]'
add payload-transcript-path-number-passes-debounce-then-crashes "$(e "$EJ" '"HARVEST_MIN_INTERVAL":"3600"')" '{"transcript_path":5}' '{}' '["cwd/_meta/learned-ledger.md","home/hv/last-ledger"]'
add root-trailing-slash "$(e "$EJ" | jq -c '.REPO_ROOT = "@CWD@/"')" "$P" "$(S cwd/t.jsonl "$T1")"
add crash-extractor-blank-command "$(e "$EJ" '"HARVEST_EXTRACTOR":"   "')" "$P" "$(S cwd/t.jsonl "$T1")"
add debounce-interval-huge "$(e "$EJ" '"HARVEST_MIN_INTERVAL":"99999999999999999999999"')" "$P" "$(S cwd/t.jsonl "$T1" home/hv/last-ledger 1)" '["cwd/_meta/learned-ledger.md","home/prompt.txt"]'
add glossary-heading-with-trailing-spaces "$(e '[{"item":"spaced title"},{"item":"fresh"}]')" "$P" "$(S cwd/t.jsonl "$T1" cwd/learning/a/GLOSSARY.md $'##   Spaced Title   \n')"
add glossary-heading-crlf "$(e '[{"item":"crlf title"},{"item":"fresh"}]')" "$P" "$(S cwd/t.jsonl "$T1" cwd/learning/a/GLOSSARY.md $'## CRLF Title\r\n')"
add ledger-crlf-rows "$(e '[{"item":"known-item"},{"item":"fresh"}]')" "$P" "$(S cwd/t.jsonl "$T1" $LEDGER $'| date | item | kind | home | status |\r\n|---|---|---|---|---|\r\n| 2026-01-01 | known-item | insight | til | queued |\r\n')"
add extractor-timeout-discards-stdout "$(e "$EJ" '"HARVEST_EXTRACTOR":"bash @HOME@/ext-hang.sh","PATH":"@HOME@/shim:@PATH@"')" "$P" "$(S cwd/t.jsonl "$T1" home/ext-hang.sh $'#!/bin/sh\ncat > "$EXT_PROMPT_FILE"\nprintf \'%s\' "$EXT_JSON"\n/bin/sleep 130\n' home/shim/sleep $'#!/bin/sh\nexec /bin/sleep 1\n')"
echo "wrote $(wc -l < "$OUT" | tr -d ' ') cases"
