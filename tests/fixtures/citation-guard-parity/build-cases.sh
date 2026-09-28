#!/usr/bin/env bash
# build-cases.sh -- (re)build the citation-guard parity corpus: a fixture tree with known
# line counts under root/, one transcript per case under transcripts/, and cases.jsonl.
# Each case's final assistant text is the thing under test; gen-expected.sh records what
# the Python hook did with it.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$HERE/root"; T="$HERE/transcripts"
mkdir -p "$R/sub" "$R/dir.d" "$T"
printf '1\n2\n3\n4\n5\n' > "$R/a.md"
printf 'x\ny\nz\n' > "$R/sub/b.py"
: > "$R/empty.txt"
printf 'one\ntwo' > "$R/noeol.txt"
printf 'ok\n' > "$R/dash-name_v2.test.js"
printf 'l1\nl2\n' > "$R/Số.md"
: > "$HERE/cases.jsonl"

# case <name> <env-json> <payload-extra-json> <assistant text>...
# Several text args become several text blocks in the LAST assistant entry.
case_() {
  local name="$1" env="$2" extra="$3"; shift 3
  local blocks; blocks=$(jq -n '$ARGS.positional | map({type:"text", text:.})' --args "$@")
  {
    jq -c -n '{type:"user", message:{content:"hi"}}'
    jq -c -n '{type:"assistant", message:{content:[{type:"text", text:"old turn cites nope.md:9"}]}}'
    jq -c -n --argjson b "$blocks" '{type:"assistant", message:{content:$b}}'
  } > "$T/$name.jsonl"
  jq -c -n --arg name "$name" --argjson env "$env" --argjson extra "$extra" \
    '{name:$name, env:$env, payload:({transcript_path:("transcripts/" + $name + ".jsonl"), cwd:"ROOT"} + $extra)}' \
    >> "$HERE/cases.jsonl"
}
E='{}'; S='{"CITATION_GUARD_STRICT":"1"}'
case_ all-resolve "$S" '{}' 'see a.md:5 and sub/b.py:1 and noeol.txt:2'
case_ past-eof "$S" '{}' 'see a.md:6 and noeol.txt:3 and empty.txt:1'
case_ line-zero "$S" '{}' 'see a.md:0 and empty.txt:0'
case_ missing-file "$S" '{}' 'see nope.md:1 and sub/none.py:2'
case_ logonly-default "$E" '{}' 'see nope.md:1'
case_ strict-true-is-not-strict '{"CITATION_GUARD_STRICT":"true"}' '{}' 'see nope.md:1'
case_ strict-space '{"CITATION_GUARD_STRICT":" 1"}' '{}' 'see nope.md:1'
case_ fenced-ignored "$S" '{}' $'before\n```\nnope.md:1\n```\nafter a.md:2'
case_ fence-spans-blocks "$S" '{}' $'x ```' $'nope.md:1 ``` y'
case_ unclosed-fence "$S" '{}' $'```\nnope.md:1'
case_ inline-ignored "$S" '{}' 'run `nope.md:1` then a.md:1'
case_ url-ignored "$S" '{}' 'see https://example.com/nope.md:1 and http://x/y.md:2 ok'
case_ clock-and-ratio "$S" '{}' 'at 10:00 ratio 3:2 and v1.2:3 and 1.5:2'
case_ word-boundary "$S" '{}' 'a.md:12abc and a.md:3, a.md:4. (a.md:99)'
case_ dedupe-order "$S" '{}' 'nope.md:2 then nope.md:1 then nope.md:2'
case_ abs-path "$S" '{}' 'see /definitely/not/here.md:1'
case_ dir-not-file "$S" '{}' 'see dir.d:1'
case_ names "$S" '{}' 'see dash-name_v2.test.js:1 and dash-name_v2.test.js:2 and Số.md:3'
case_ huge-line "$S" '{}' 'see a.md:99999999999999999999'
case_ root-override '{"CITATION_GUARD_STRICT":"1","CITATION_GUARD_ROOT":"ROOT/sub"}' '{}' 'see b.py:3 and a.md:1'
case_ session-id "$S" '{"sessionId":"S1"}' 'see nope.md:1'
case_ session-underscore "$S" '{"session_id":"S2"}' 'see nope.md:1'
case_ no-refs "$S" '{}' 'nothing to check here'
case_ multi-block "$S" '{}' 'first nope.md:1' 'second a.md:9'
case_ backticks-unbalanced "$S" '{}' 'a `b nope.md:1 and a.md:2'
case_ trailing-colon "$S" '{}' 'file a.md: and a.md:'

# payload-shape cases that need no transcript
jq -c -n '{name:"no-transcript-path", env:{"CITATION_GUARD_STRICT":"1"}, payload:{cwd:"ROOT"}}' >> "$HERE/cases.jsonl"
jq -c -n '{name:"missing-transcript", env:{"CITATION_GUARD_STRICT":"1"}, payload:{transcript_path:"transcripts/does-not-exist.jsonl", cwd:"ROOT"}}' >> "$HERE/cases.jsonl"
jq -c -n '{name:"malformed-stdin", env:{"CITATION_GUARD_STRICT":"1"}, payload:"RAW:{not json"}' >> "$HERE/cases.jsonl"

# transcript-shape cases
{ echo 'not json'; echo; jq -c -n '{type:"assistant", message:{content:"a plain string, nope.md:1"}}'; } > "$T/string-content.jsonl"
jq -c -n '{name:"string-content", env:{"CITATION_GUARD_STRICT":"1"}, payload:{transcript_path:"transcripts/string-content.jsonl", cwd:"ROOT"}}' >> "$HERE/cases.jsonl"
{ jq -c -n '{type:"assistant", message:{content:[{type:"text", text:"nope.md:1"}]}}'; jq -c -n '{type:"assistant", message:{content:[{type:"tool_use", name:"x"}]}}'; } > "$T/last-has-no-text.jsonl"
jq -c -n '{name:"last-has-no-text", env:{"CITATION_GUARD_STRICT":"1"}, payload:{transcript_path:"transcripts/last-has-no-text.jsonl", cwd:"ROOT"}}' >> "$HERE/cases.jsonl"
jq -c -n '{type:"user", message:{content:"nope.md:1"}}' > "$T/no-assistant.jsonl"
jq -c -n '{name:"no-assistant", env:{"CITATION_GUARD_STRICT":"1"}, payload:{transcript_path:"transcripts/no-assistant.jsonl", cwd:"ROOT"}}' >> "$HERE/cases.jsonl"


# round-1 pre-emptions: Unicode word boundaries and digits, CRLF, truthiness, log path
printf 'a\r\nb\r\nc\r\n' > "$R/crlf.txt"
case_ unicode-after-digit "$S" '{}' 'see a.md:3é and a.md:9é and a.md:7_x and a.md:8'
case_ crlf-lines "$S" '{}' 'see crlf.txt:3 and crlf.txt:4'
case_ root-empty-falls-back '{"CITATION_GUARD_STRICT":"1","CITATION_GUARD_ROOT":""}' '{}' 'see sub/b.py:4'
case_ session-empty-falls-back "$S" '{"sessionId":"","session_id":"S3"}' 'see nope.md:1'
case_ log-set-empty '{"CITATION_GUARD_STRICT":"1","CITATION_GUARD_LOG":""}' '{}' 'see nope.md:1'
case_ log-relative '{"CITATION_GUARD_STRICT":"1","CITATION_GUARD_LOG":"rel.log"}' '{}' 'see nope.md:1'
case_ log-unset-default-home '{"CITATION_GUARD_LOG":null}' '{}' 'see nope.md:1'
case_ cwd-absent-uses-pwd "$S" '{"cwd":null}' 'see a.md:6'
case_ nbsp-url '{"CITATION_GUARD_STRICT":"1"}' '{}' $'see https://x.y/p nope.md:1 end'
jq -c -n '{name:"non-object-payload", env:{"CITATION_GUARD_STRICT":"1"}, payload:"RAW:[1,2]"}' >> "$HERE/cases.jsonl"
echo "built $(wc -l < "$HERE/cases.jsonl" | tr -d ' ') cases (with pre-emptions)"

# validation round 1 (SPEC-356 rev 2)
case_ inline-multiline-a "$S" '{}' $'the ` char\nsee nope.md:1 and ` here'
case_ inline-multiline-b "$S" '{}' $'run `x\nnope.md:1\ny` end'
case_ url-nnbsp "$S" '{}' $'see https://x.y/p nope.md:1 end'
case_ url-thin-space "$S" '{}' $'see https://x.y/p nope.md:2 end'
case_ url-zwsp "$S" '{}' $'see https://x.y/p​nope.md:3 end'
case_ leading-zeros "$S" '{}' 'nope.md:07 and nope.md:7 and a.md:006'
case_ four-backtick-fence "$S" '{}' $'````md\n```js\ncode nope.md:1\n```\n````'
case_ unicode-punct-after "$S" '{}' $'see “a.md:9” and a.md:8—x and a.md:7…'
case_ cwd-empty-string "$S" '{"cwd":""}' 'see a.md:6'
{ jq -c -n '{type:"assistant", message:{content:[{type:"text", text:"fine"}]}}'; echo 'garbage line'; jq -c -n '{type:"assistant", message:{content:[{type:"text", text:"now nope.md:1"}]}}'; } > "$T/nonjson-before-final.jsonl"
{ jq -c -n '{type:"assistant", message:{content:[{type:"text", text:"now nope.md:1"}]}}'; printf '{"type":"assist'; } > "$T/truncated-last-line.jsonl"
{ jq -c -n '{type:"assistant", message:{content:[{type:"text", text:"old nope.md:1"}]}}'; jq -c -n '{type:"assistant", message:{content:[{type:"text", text:""}]}}'; } > "$T/empty-text-block-last.jsonl"
{ jq -c -n '{type:"assistant", message:{content:[{type:"text", text:"old nope.md:1"}]}}'; jq -c -n '{type:"assistant", message:{content:[{type:"text"}]}}'; } > "$T/text-block-no-key.jsonl"
{ jq -c -n '{type:"assistant", message:{content:[{type:"text", text:"old nope.md:1"}]}}'; echo '[1,2]'; } > "$T/crash-nonobject-line.jsonl"
{ jq -c -n '{type:"assistant", message:{content:[{type:"text", text:"old nope.md:1"}]}}'; jq -c -n '{type:"assistant", message:"a string"}'; } > "$T/crash-message-string.jsonl"
{ jq -c -n '{type:"assistant", message:{content:[{type:"text", text:null}]}}'; } > "$T/crash-text-null.jsonl"
for n in nonjson-before-final truncated-last-line empty-text-block-last text-block-no-key crash-nonobject-line crash-message-string crash-text-null; do
  jq -c -n --arg n "$n" '{name:$n, env:{"CITATION_GUARD_STRICT":"1"}, payload:{transcript_path:("transcripts/" + $n + ".jsonl"), cwd:"ROOT"}}' >> "$HERE/cases.jsonl"
done

# validation round 2 (SPEC-356 rev 3)
case_ line-zero-missing "$S" '{}' 'see nope.md:0 and nope.md:00 and a.md:00'
{ jq -c -n '{type:"assistant", message:{content:[{type:"text", text:null}]}}'; jq -c -n '{type:"assistant", message:{content:[{type:"text", text:"now nope.md:1"}]}}'; } > "$T/crash-text-null-before-ref.jsonl"
jq -c -n '{name:"crash-text-null-before-ref", env:{"CITATION_GUARD_STRICT":"1"}, payload:{transcript_path:"transcripts/crash-text-null-before-ref.jsonl", cwd:"ROOT"}}' >> "$HERE/cases.jsonl"

# fresh review: a lone high surrogate in the final text (json.loads accepts it)
{ jq -c -n '{type:"assistant", message:{content:[{type:"text", text:"old gone.md:9"}]}}'; printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"done \ud83d ok"}]}}'; } > "$T/lone-surrogate-final.jsonl"
jq -c -n '{name:"lone-surrogate-final", env:{"CITATION_GUARD_STRICT":"1"}, payload:{transcript_path:"transcripts/lone-surrogate-final.jsonl", cwd:"ROOT"}}' >> "$HERE/cases.jsonl"
echo "built $(wc -l < "$HERE/cases.jsonl" | tr -d ' ') cases (review folded)"
